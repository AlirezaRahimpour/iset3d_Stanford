function [status, result] = render(obj, renderCommand, outputFolder)
% Render radiance and depth using the dockerWrapper method
%
% Synopsis
%   [status, result] = render(obj, renderCommand, outputFolder)
%
% Inputs
%  obj - a dockerWrapper
%  renderCommand - the PBRT command for rendering
%  outputFolder  - the output for the rendered data
%
% Outputs
%  status - 0 means it worked well
%  result - Stdout text returned here
%
% Notes:
%   (Author?) Currently we have an issue where GPU rendering ignores
%   objects that have ActiveTranforms. Maybe scan for those & set
%   container back to CPU (perhaps ideally a beefy, remote, CPU).
%
% See also
%  piRender, sceneEye.render
%
% See debugging note at end.

%% Build up the render command

% How chatty to the stdout
verbose = obj.verbosity; % 0, 1, 2

% Determine the container
if obj.gpuRendering
    useContainer = obj.getContainer('PBRT-GPU');
    renderCommand = strrep(renderCommand, 'pbrt ', 'pbrt --gpu ');
else
    useContainer = obj.getContainer('PBRT-CPU');
end

%% Windows doesn't seem to like the t flag
if ispc,     flags = '-i ';
else,        flags = '-it ';
end

[~, sceneDir, ~] = fileparts(outputFolder);

% ASSUME that if we supply a context it is on a Linux server
nativeFolder = outputFolder;
if ~isempty(dockerWrapper.staticVar('get','renderContext',''))
    useContext = dockerWrapper.staticVar('get','renderContext','');
else
    useContext = getpref('docker','renderContext','');
end
% container is Linux, so convert
outputFolder = dockerWrapper.pathToLinux(outputFolder);

% sync data over
if ~obj.localRender
    % Running remotely.
    if ispc
        rSync = 'wsl rsync';
        nativeFolder = [obj.localRoot outputFolder '/'];
    else
        rSync = 'rsync';
    end
    if isempty(obj.remoteRoot)
        obj.remoteRoot = '~';
        % if no remote root, then we need to look up our local root and use it!
    end
    if ~isempty(obj.remoteUser)
        remoteAddress = [obj.remoteUser '@' obj.remoteMachine];
    else
        remoteAddress = obj.remoteMachine;
    end

    % in the case of Mac (& Linux?) outputFolder includes both
    % our iset dir and then the relative path
    [~, sceneDir, ~] = fileparts(outputFolder);
    remoteScenePath = dockerWrapper.pathToLinux(fullfile(obj.remoteRoot, obj.relativeScenePath, sceneDir));

    %remoteScenePath = [obj.remoteRoot outputFolder];
    remoteScenePath = strrep(remoteScenePath, '//', '/');
    remoteScene = [remoteAddress ':' remoteScenePath '/'];

    % use -c for checksum if clocks & file times won't match
    % using -z for compression, but doesn't seem to make a difference?
    putData = tic;
    speedup = ' --protocol=29  -e "ssh -x -T -o Compression=no"';
    % -c arcfour might help if we have it on both sides
    if ismac || isunix
        % We needed the extra slash for the mac.  But still investigation
        % (DJC)
        putCommand = sprintf('%s %s -r -t %s %s',rSync, speedup, [nativeFolder,'/'], remoteScene);
    else
        putCommand = sprintf('%s %s -r -t %s %s',rSync, speedup, nativeFolder, remoteScene);
    end

    if verbose > 0
        fprintf('Put: %s ...\n', putCommand);
    end
    [rStatus, rResult] = system(putCommand);

    if verbose > 0
        fprintf('Done (%4.2f sec)\n', toc(putData))
    end
    if rStatus ~= 0, error(rResult); end
    
    renderStart = tic;
    % our output folder path starts from root, not from where the volume is
    % mounted
    shortOut = dockerWrapper.pathToLinux(fullfile(obj.relativeScenePath, sceneDir));

    % need to cd to our scene, and remove all old renders
    % some leftover files can start with "." so need to get them also
    containerCommand = sprintf('docker --context %s exec %s %s sh -c "cd %s && rm -rf renderings/{*,.*}  && %s"',...
        useContext, flags, useContainer, shortOut, renderCommand);
    if verbose > 0
        fprintf('Command: %s\n', containerCommand);
    end

    if verbose > 1
        [status, result] = system(containerCommand, '-echo');
        fprintf('Rendered remotely in: %4.2f sec\n', toc(renderStart))
        fprintf('Returned parameter result is\n***\n%s', result);
    elseif verbose == 1
        [status, result] = system(containerCommand);
        if status == 0
            fprintf('Rendered remotely in: %4.2f sec\n', toc(renderStart))
        else
            fprintf("Error Rendering: %s", result);
        end
    else
        [status, result] = system(containerCommand);
    end
    if status == 0 && ~isempty(obj.remoteMachine)

        % sync data back -- renderings sub-folder
        % This assumes that all output is in that folder!
        getOutput = tic;
        % this speedup works for put, but so far not for pull
        %speedup = ' --protocol=29  -e "ssh -x -T -o Compression=no"';
        speedup = '';
        pullCommand = sprintf('%s -r %s %s %s',rSync, speedup, ...
            [remoteScene 'renderings/'], dockerWrapper.pathToLinux(fullfile(nativeFolder, 'renderings')));
        if verbose > 0
            fprintf('Pull: %s ...\n', pullCommand);
        end

        % bring back results
        system(pullCommand);
        if verbose > 0
            fprintf('done (%6.2f sec)\n', toc(getOutput))
        end
    end
else
    % Running locally.        
    shortOut = dockerWrapper.pathToLinux(fullfile(obj.relativeScenePath,sceneDir));
    containerCommand = sprintf('docker --context default exec %s %s sh -c "cd %s && %s"', flags, useContainer, shortOut, renderCommand);    
    
    tic;
    [status, result] = system(containerCommand);
    if verbose > 0
        fprintf('Rendered time %6.2f\n', toc)
    end
end

%% For debugging.  Will write a method to just return these before long (BW).

fprintf('\n------------------\n');
fprintf('Container command: %s\n',containerCommand);
fprintf('PBRT command: %s\n',renderCommand);
fprintf('\n------------------\n');


end

