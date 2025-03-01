classdef dockerWrapper < handle
    %DOCKERWRAPPER A class to manage ISET3d-v4 rendering
    %
    % This class manages how we run PBRT and other tools in Linux docker
    % containers in ISET3d (version 4). At present, we manage these cases:
    %
    %   * a remote (Linux) server with a GPU,
    %   * a remote (Linux) server with a CPU,
    %   * your local (Linux/Mac) computer with a GPU,
    %   * your local computer with a CPU, and
    %
    %   [FUTURE, TBD:]
    %   * your local computer with PBRT installed and no docker at all.
    %
    % This source code is under active development (May, 2022).
    %
    % Description:
    %
    % The dockerWrapper class is used by piWRS() and piRender(). These
    % functions specify the docker images that run either locally or
    % remotely. For instructions on how to set up a computer to run
    % on a remote, see the ISET3d-v4 wiki pages.
    %
    % To run on a remote machine, we launch a Docker image on that
    % machine as a persistent, named, container. Calls to piRender()
    % use dockerWrapper to store the name and status of that remote
    % container.  By running in a persistent container, we avoid the
    % startup overhead (which is more than 20 seconds for a GPU image).
    %
    % Users often call the same remote machine and GPU across multiple
    % days/sessions, the default parameters for docker execution are stored
    % in the Matlab prefs.  These are saved by Matlab between sessions. You
    % can set and get these parameters using the Matlab setpref/getpref
    % commands.
    %
    % For the moment, we are storing these parameters within the key string
    % 'docker', though we are discussing storing them within the string
    % 'iset3d'.
    %
    % Default parameters can be retrieved from prefs using
    %
    %   getpref('docker',<paramName>,[default value]);
    %
    % Parameters that need to be passed in or set by default:
    %
    %   remoteMachine -- (if any) name of remote machine to render on
    %   remoteImage   -- (if any) GPU-specific docker image on remote machine
    %   gpuRendering    -- set to true to force GPU rendering
    %                   -- set to false to force CPU rendering
    %                   -- by default will use a local GPU if available
    %
    % Optional parameters
    %  localRender -- Render on your local machine (default false)
    %
    %  remoteUser  -- username on remote machine if different from the
    %                   username on the local machine
    %  renderContext -- a docker context that defines the remote
    %                   renderer; only set this if it is  different
    %                   from the default that is created for you
    %                   (unusual)
    %  remoteRoot     -- needed if differs from the return from
    %                    piRootPath
    %  remoteImageTag -- defaults to :latest
    %  whichGPU    -- for multi-gpu rendering systems, select a specific
    %             GPU on the remote machine. Use device number (e.g.
    %             0, 1, etc.) THe choice -1 defaults, but it is
    %             probably best for you to choose.
    %
    %  localImageTag  -- defaults to :latest
    %  localRoot   -- (only for WSL) the /mnt path to the Windows piRoot
    %
    %  localVolumePath -- For running scenes outside if /iset3d-v4/local
    %
    % Additional NOTES
    %
    % * Use dockerWrapper.setPrefs and dockerWrapper.getPrefs to
    % interact with the Matlab prefs that determine the defaults.  The
    % defaults are used when creating a new dockerWrapper.
    %
    % * It is possible to create a dockerWrapper and then manually change
    % the parameters.  We recently made the dockerWrapper variables
    % public, not private.
    %
    % * To shut down stranded local containers, on the command line
    % run:
    %
    %    docker container prune
    %
    % That works for imgtool stranded containers. There can sometimes
    % be stranded rendering containers which may be on your rendering
    % server -- in the event that Matlab doesn't shut down properly.
    % Those can be pruned by running the same command on the server.
    % (or wait for DJC to prune them on the server every few days:))
    %
    % Useful docker tips
    %    docker ps
    %    docker images
    %    docker -it exec <dockerID> bash 
    %      (https://stackoverflow.com/questions/30172605/how-do-i-get-into-a-docker-containers-shell)
    %
    % Examples:
    %
    % D.Cardinal -- Stanford University -- 2021-2022
    %
    % See also
    %   setpref/getpref

    %% Notes
    %{
      Solution:  Local Docker desktop was not running on my mac
      ------------------------------
      Container command: docker --context default exec -it  pbrt-cpu-wandell12684 sh -c "cd /iset/iset3d-v4/local/ChessSet && pbrt --outfile renderings/ChessSet.exr ChessSet.pbrt"
      PBRT command: pbrt --outfile renderings/ChessSet.exr ChessSet.pbrt

      ------------------
      Warning: Docker did not run correctly 
      > In piRender (line 251)
      In piWRS (line 106)
      In v_DockerWrapper (line 83) 
      Status:
          1
       Result:
       Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
    %}

    %% Methods
    properties (SetAccess = public)

        % by default we assume our container is built to run pbrt
        % this gets changed to run imgtool, assimp, etc.
        command = 'pbrt';

        inputFile = '';

        % This should be over-ridden with the appropriate filenams
        % for example: <scene_name>.exr
        outputFile = 'pbrt_output.exr';

        % This is the flag pbrt needs to specify it's output
        % Can be over-ridden if the command takes a different output flag
        outputFilePrefix = '--outfile';

        % NOTE: Defaults set here are values we always want. Values the
        % user might over-ride from their prefs, we declare the property
        % here, and set the value using getpref in the Constructor.

        % Right now pbrt only supports Linux containers
        containerType = 'linux'; % default, even on Windows

        % sometimes we need a subsequent conversion command.  What does
        % that mean?
        dockerCommand = 'docker run'; 
        dockerFlags = '';

        dockerContainerName = '';
        dockerContainerID = '';

        % Better comment needed.
        % default image is cpu on x64 architecture
        dockerImageRender = '';        % set based on local machine
        
        % The defaults for these are set in the constructor
        gpuRendering;
        whichGPU;

        % these relate to remote/server rendering
        remoteMachine;  % for syncing the data
        remoteRoot;      % we need to know where to map on the remote system
        remoteUser;     % use for rsync & ssh/docker
        remoteImage;    % A GPU image on the remote server
        remoteCPUImage; % A CPU image on the remote server

        % By default we assume that we want :latest, but :stable is
        % typically also an option incase something is broken
        remoteImageTag;  % Seems to apply to both GPU and CPU?

        % A render context is important for the case where we want to
        % access multiple servers over time (say beluga & mux, or mux &
        % gray, etc). Contexts are created via docker on the local system,
        % and if needed one is created by default
        renderContext;
        defaultContext;   % docker context used for everything else
        localImageName;
        localRoot  = '';  % dockerWrapper.defaultLocalRoot();
        localRender;
        localImageTag;    % Does this over-ride a tag that is already set?

        localVolumePath  = '';

        workingDirectory = '';
        targetVolumePath = '';

        relativeScenePath;

        verbosity;  % 0,1 or 2.  How much to print.  Might change

    end

    methods

        % Constructor method
        function aDocker = dockerWrapper(varargin)
            %Docker Construct an instance of the dockerWrapper class
            %
            %  All dynamic properties should be initialized here!
            %  If they are initialized in properties they get messed up
            %  (DJC).
            %
            %
            % We typically want 'default' to be the docker context
            % for everything except rendering
            aDocker.defaultContext = dockerWrapper.setContext(getpref('docker','defaultContext', 'default'));
            aDocker.gpuRendering = getpref('docker', 'gpuRendering', true);
            aDocker.localImageName   =  getpref('docker','localImage','');

            aDocker.whichGPU = getpref('docker','whichGPU',0); % -1 is use any

            % these relate to remote/server rendering
            aDocker.remoteMachine  = getpref('docker','remoteMachine',''); % for syncing the data
            aDocker.remoteUser     = getpref('docker','remoteUser',''); % use for rsync & ssh/docker
            aDocker.remoteImage    = getpref('docker','remoteImage',''); % use to specify a GPU-specific image on server
            aDocker.remoteImageTag = 'latest';
            if ispc
                % On Windows can not specify ~ for a mount point, even if
                % it is actually on a Linux server, so we guess!
                aDocker.remoteRoot     = getpref('docker','remoteRoot',dockerWrapper.pathToLinux(fullfile('/home',aDocker.getUserName()))); % we need to know where to map on the remote system
            else
                aDocker.remoteRoot     = getpref('docker','remoteRoot','~'); % we need to know where to map on the remote system
            end
            aDocker.remoteCPUImage = 'digitalprodev/pbrt-v4-cpu';

            % You can run scenes from other locations beside
            % iset3d-v4/local by setting this.
            aDocker.localVolumePath = getpref('docker','localVolumePath',piDirGet('local'));
            aDocker.renderContext = getpref('docker','renderContext','remote-mux');
            % because our Docker image is Linux-based, we need to find
            % our local scene path and then convert to linux if we're on
            % Windows
            aDocker.relativeScenePath = dockerWrapper.pathToLinux(piDirGet('server local'));

            aDocker.localRender = getpref('docker','localRender',false);
            aDocker.localImageTag = 'latest';
            aDocker.localRoot = getpref('docker','localRoot','');

            aDocker.verbosity = 1;  % 0,1 or 2.  How much to print.  Might change

            % default for flags
            if ispc
                aDocker.dockerFlags = '-i --rm';
            else
                aDocker.dockerFlags = '-ti --rm';
            end

            % I don't think we should fail in a pure default case?
            % Also allow renderString pref for backward compatibility
            if ~isempty(varargin)
                for ii=1:2:numel(varargin)
                    aDocker.(varargin{ii}) = varargin{ii+1};
                end
            end

            if isempty(aDocker.localImageName)
                %
                if aDocker.gpuRendering
                    aDocker.localImageName = aDocker.getPBRTImage('GPU');
                else
                    aDocker.localImageName = aDocker.getPBRTImage('CPU');
                end
            end

        end

        function prefsave(obj)
            % Save the current dockerWrapper settings in the Matlab
            % prefs (under iset3d).  We should probably check if there
            % is a 'docker' prefs and do something about that.

            disp('Saving prefs to "docker"');
            setpref('docker','localRender',obj.localRender);

            setpref('docker','remoteMachine',obj.remoteMachine);
            setpref('docker','remoteRoot',obj.remoteRoot);
            setpref('docker','remoteUser',obj.remoteUser);
            setpref('docker','remoteImageTag',obj.remoteImageTag);

            setpref('docker','gpuRendering',obj.gpuRendering);
            setpref('docker','whichGPU',obj.whichGPU);

            setpref('docker','localImageTag',obj.localImageTag);
            setpref('docker','localRoot',obj.localRoot);

            setpref('docker','verbosity',obj.verbosity);

        end

        function prefread(obj)
            % Read the current dockerWrapper settings in the Matlab
            % prefs (under iset3d).  We should probably check if there
            % is a 'docker' prefs and do something about that.

            disp('Reading prefs from "docker"');
            obj.localRender = getpref('docker','localRender',0);

            obj.remoteMachine = getpref('docker','remoteMachine','');
            obj.remoteRoot    = getpref('docker','remoteRoot','');
            obj.remoteUser    = getpref('docker','remoteUser','');
            obj.remoteImageTag= getpref('docker','remoteImageTag','latest');

            obj.gpuRendering = getpref('docker','gpuRendering',1);
            obj.whichGPU     = getpref('docker','whichGPU',0);

            obj.localImageTag = getpref('docker','localImageTag','latest');

            obj.verbosity = getpref('docker','verbosity',1);

        end
    end


    methods (Static=true)
        %% Static functions
        %
        % Static functions do not have an 'obj' argument.
        %
        % Matlab requires listing all static functions in a separate file.
        % The definitions must be here.
        %
        % Methods defined in this file, static or not, do not need to be
        % listed here.

        setPrefs(varargin);
        getPrefs(varargin);
        dockerImage = localImage();
        [dockerExists, status, result] = exists();  % Like piDockerExists

        %% Default servers
        function useServer = vistalabDefaultServer()
            useServer = 'muxreconrt.stanford.edu';
        end

        %% This is used for wsl commands under Windows, which need
        % to know where to find the drive root.
        function localRoot = defaultLocalRoot()
            if ispc
                localRoot = getpref('docker','localRoot','/mnt/c'); % Windows default
            else
                localRoot = getpref('docker','localRoot',''); % Linux/Mac default
            end
        end
        
        %% reset - Resets the running Docker containers
        function reset()
            % Calls the method 'cleanup' and sets several parameters
            % to empty.  The cleanup is called if there is a static
            % variable defined for PBRT-GPU and/or PBRT-CPU.

            % TODO: We should remove any existing containers here
            % to sweep up after ourselves.
            if ~isempty(dockerWrapper.staticVar('get','PBRT-GPU',''))
                dockerWrapper.cleanup(dockerWrapper.staticVar('get','PBRT-GPU',''));
                dockerWrapper.staticVar('set', 'PBRT-GPU', '');
            end
            if ~isempty(dockerWrapper.staticVar('get','PBRT-CPU',''))
                dockerWrapper.cleanup(dockerWrapper.staticVar('get','PBRT-CPU',''));
                dockerWrapper.staticVar('set', 'PBRT-CPU', '');
            end

            % Empty out the static variables
            dockerWrapper.staticVar('set', 'cpuContainer', '');
            dockerWrapper.staticVar('set', 'gpuContainer', '');
            dockerWrapper.staticVar('set', 'renderContext', '');
            dockerWrapper.setContext('default'); % in case it has been set
        end

        %% cleanup
        function cleanup(containerName)
            if ~isempty(dockerWrapper.staticVar('get','renderContext'))
                contextFlag = sprintf(' --context %s ', dockerWrapper.staticVar('get','renderContext'));
            else
                contextFlag = '';
            end

            % Removes the Docker container in renderContext
            cleanupCmd = sprintf('docker %s rm -f %s', ...
                contextFlag, containerName);
            [status, result] = system(cleanupCmd);

            if status == 0
                sprintf('Removed container %s\n',containerName);
            else
                disp("Failed to cleanup.\n System message:\n %s", result);
            end
        end

        %% Interact with persistent variables
        function retVal = staticVar(action, varname, value)
            % Manages interactions with the persistent variables
            %
            %    gpuContainer, cpuContainer and renderContext
            %
            % Actions are 'set' or 'get' (default).  

            persistent gpuContainer;
            persistent cpuContainer;
            persistent renderContext;
            switch varname
                case 'PBRT-GPU'
                    if isequal(action, 'set')
                        gpuContainer = value;
                    end
                    retVal = gpuContainer;
                case 'PBRT-CPU'
                    if isequal(action, 'set')
                        cpuContainer = value;
                    end
                    retVal = cpuContainer;
                case 'renderContext'
                    if isequal(action, 'set')
                        renderContext = value;
                    end
                    retVal = renderContext;
            end
        end

        %% Format path strings
        function output = pathToLinux(inputPath)
            % On Windows the Docker
            % paths are Linux-format, so the native fullfile and fileparts
            % don't work right.
            if ispc
                if isequal(fullfile(inputPath), inputPath)
                    if numel(inputPath) > 3 && isequal(inputPath(2:3),':\')
                        % assume we have a drive letter
                        output = inputPath(3:end);
                    else
                        output = inputPath;
                    end
                    output = strrep(output, '\','/');
                else
                    output = strrep(inputPath, '\','/');
                end
            else
                output = inputPath;
            end

        end

        %% For switching docker to other (typically remote) context
        % and then back. Static as it is system-wide
        function newContext = setContext(useContext)
            % dummy return values otherwise we get output to console by
            % default
            if ~isempty(useContext)
                [~, ~] = system(sprintf('docker context use %s', useContext));
                newContext = useContext;
            else
                [~, ~] = system('docker context use default');
                newContext = 'default';
            end
        end

    end

    methods (Static = false)
        %% These have an obj argument and therefore they are not static.

        %% Start PBRT
        function ourContainer = startPBRT(obj, processorType)
            % Start the docker container remotely

            verbose = obj.verbosity;
            if isequal(processorType, 'GPU')
                useImage = obj.getPBRTImage('GPU');
            else
                useImage = obj.getPBRTImage('CPU');
            end
            rng('shuffle'); % make random numbers random
            uniqueid = randi(20000);
            if ispc
                uName = ['Windows' int2str(uniqueid)];
            else
                uName = [getenv('USER') int2str(uniqueid)];
            end
            % All our new images currently have libraries pre-loaded
            legacyImages = false;
            if ~legacyImages % contains(useImage, 'shared')
                % we don't need to mount libraries
                cudalib = '';
            else
                cudalib = ['-v /usr/lib/x86_64-linux-gnu/libnvoptix.so.1:/usr/lib/x86_64-linux-gnu/libnvoptix.so.1 ',...
                    '-v /usr/lib/x86_64-linux-gnu/libnvoptix.so.470.57.02:/usr/lib/x86_64-linux-gnu/libnvoptix.so.470.57.02 ',...
                    '-v /usr/lib/x86_64-linux-gnu/libnvidia-rtcore.so.470.57.02:/usr/lib/x86_64-linux-gnu/libnvidia-rtcore.so.470.57.02'];
            end
            if isequal(processorType, 'GPU')
                ourContainer = ['pbrt-gpu-' uName];
            else
                ourContainer = ['pbrt-cpu-' uName];
            end

            % Because we are now running Docker as a background task, we
            % need to be able to re-use it for all scenes so we need to
            % volume map all of /local
            %
            % if running Docker remotely then need to figure out correct
            % path
            %
            % One tricky bit is that on Windows, the mount point is the
            % remote server path, but later we need to use the WSL path for
            % rsync
            %
            % hostLocalPath is the host file system for
            % <iset3d-v4>/local containerLocalPath is the container
            % path for <iset3d-v4>/local (normally under /iset)
            %
            % BW:  Why do we change the variable name from
            % localVolumePath to hostLocalPath? Would it be OK to
            % use hostLocalPath everywhere?  Or is there a distinction
            % between local/host?  
            if obj.localRender
                hostLocalPath = obj.localVolumePath;
            else
                if ~isempty(obj.remoteRoot)
                    hostLocalPath = dockerWrapper.pathToLinux(fullfile(obj.remoteRoot, obj.relativeScenePath));
                else
                    hostLocalPath = piDirGet('local');
                    warning("Set Remote Root for you to: %s\n",hostLocalPath);
                end
            end

            containerLocalPath = dockerWrapper.pathToLinux(obj.relativeScenePath);

            volumeMap = sprintf("-v %s:%s", hostLocalPath, containerLocalPath);
            placeholderCommand = 'bash';

            % We use the default context for local docker containers
            if obj.localRender
                contextFlag = ' --context default ';
            else
                % Rendering remotely.
                % Have to track user set context somehow
                % probably static var should be set from prefs
                % automatically...
                if isempty(obj.staticVar('get','renderContext'))
                    contextFlag = [' --context ' getpref('docker','renderContext','remote-mux')];
                    obj.staticVar('set','renderContext',getpref('docker','renderContext','remote-mux'));
                else
                    contextFlag = [' --context ' obj.staticVar('get','renderContext')];
                end
            end

            if isequal(processorType, 'GPU')
                % want: --gpus '"device=#"'
                gpuString = sprintf(' --gpus device=%s ',num2str(obj.whichGPU));
                dCommand = sprintf('docker %s run -d -it %s --name %s  %s', contextFlag, gpuString, ourContainer, volumeMap);
                cmd = sprintf('%s %s %s %s', dCommand, cudalib, useImage, placeholderCommand);
            else
                dCommand = sprintf('docker %s run -d -it --name %s %s', contextFlag, ourContainer, volumeMap);
                cmd = sprintf('%s %s %s', dCommand, useImage, placeholderCommand);
            end

            % if we are not connected to the remote machine, or there is
            % something wrong with the context, this hangs. Matlab system
            % doesn't have a timeout flag, but it'd be good if we could
            % find a way to validate context & server that errors out
            % more gracefully. TBD
            [status, result] = system(cmd);
            if verbose > 0
                fprintf("Started Docker (status %d): %s\n", status, cmd);
            end
            if status == 0
                obj.dockerContainerID = result; % hex name for it
                return;
            else
                warning("Failed to start Docker container with message: %s", result);
            end
        end


        %% The container name for different types of docker runs.  
        function containerName = getContainer(obj,containerType)
            
            % Either PBRT with a GPU or a CPU
            switch containerType
                case 'PBRT-GPU'
                    if isempty(obj.staticVar('get', 'PBRT-GPU', ''))
                        % Start the container and set its name
                        obj.staticVar('set','PBRT-GPU', obj.startPBRT('GPU'));
                    end

                    % If there is a render context, get it.
                    if ~isempty(obj.renderContext)
                        cFlag = ['--context ' obj.renderContext];
                    else
                        warning('No context flag found.  Consider renderContext to save startup.')
                        cFlag = '';
                    end

                    % Figure out the container name using a docker ps call
                    % in the context.
                    [~, result] = system(sprintf("docker %s ps | grep %s", cFlag, obj.staticVar('get','PBRT-GPU', '')));

                    if strlength(result) == 0
                        % Couldn't find it.  So try starting it.
                        % This likely means it got killed, or the server
                        % rebooted or similar.  So we start it.
                        obj.staticVar('set','PBRT-GPU', obj.startPBRT('GPU'));
                    end

                    % At this point, we must have it.
                    containerName = obj.staticVar('get','PBRT-GPU', '');

                case 'PBRT-CPU'
                    % Similar logic to above.
                    if isempty(obj.staticVar('get', 'PBRT-CPU', ''))
                        obj.staticVar('set','PBRT-CPU', obj.startPBRT('CPU'));
                    end

                    % Need to use render context here!
                    if ~isempty(dockerWrapper.staticVar('get','renderContext'))
                        cFlag = ['--context ' dockerWrapper.staticVar('get','renderContext')];
                    else
                        cFlag = '';
                    end

                    [~, result] = system(sprintf("docker %s ps | grep %s", cFlag, obj.staticVar('get','PBRT-CPU', '')));
                    if strlength(result) == 0
                        obj.staticVar('set','PBRT-CPU', obj.startPBRT('CPU'));
                    end
                    containerName = obj.staticVar('get', 'PBRT-CPU', '');
                otherwise
                    warning("No container found");

            end
        end

        %% Get the name of the docker image.
        function useDockerImage = getPBRTImage(obj, processorType)
            % Returns the name of the docker image, both for the case of
            % local and remote execution.
            %

            if ~obj.localRender && obj.gpuRendering
                % We are running remotely and want GPU, we try to figure out which
                % docker image to use.
                if ~isempty(obj.remoteImage)
                    % If a remoteImage is already set, that is what we use
                    useDockerImage = obj.remoteImage;
                    return;
                else
                    % Try to figure it out and return it.
                    obj.getRenderer;
                    useDockerImage = obj.remoteImage;
                    return;
                end
            else
                % If we are here, we are running locally or remote CPU.
                if obj.localRender && ~isempty(obj.localImageName)
                    % If this is set, use it.
                    useDockerImage = obj.localImageName;
                    return;
                else
                    % Running locally and no advice from the user.
                    if isequal(processorType, 'GPU') && obj.gpuRendering == true
                        % They have asked for a GPU, so we try to figure
                        % out the local GPU situation.
                        [GPUCheck, GPUModel] = ...
                            system(sprintf('nvidia-smi --query-gpu=name --format=csv,noheader -i %d',obj.whichGPU));
                        try
                            ourGPU = gpuDevice();
                            if ourGPU.ComputeCapability < 5.3 % minimum for PBRT on GPU
                                GPUCheck = -1;
                            end
                        catch
                            % GPU acceleration with Parallel Computing Toolbox is not supported on macOS.
                        end

                        % WE CAN ONLY USE GPUs ON LINUX FOR NOW
                        if ~GPUCheck && ~ispc
                            % A GPU is available.
                            obj.gpuRendering = true;

                            % Switch based on first GPU available
                            % really should enumerate and look for the best one, I think
                            gpuModels = strsplit(ieParamFormat(strtrim(GPUModel)));

                            switch gpuModels{1} % find the model of our GPU
                                case {'teslat4', 'quadrot2000'}
                                    useDockerImage = 'camerasimulation/pbrt-v4-gpu-t4';
                                case {'geforcertx3070', 'nvidiageforcertx3070'}
                                    useDockerImage = 'digitalprodev/pbrt-v4-gpu-ampere-mux';
                                case {'geforcertx3090', 'nvidiageforcertx3090'}
                                    useDockerImage = 'digitalprodev/pbrt-v4-gpu-ampere-mux';
                                case {'geforcertx2080', 'nvidiageforcertx2080', ...
                                        'geforcertx2080ti', 'nvidiageforcertx2080ti'}
                                    useDockerImage = 'digitalprodev/pbrt-v4-gpu-volta-mux';
                                case {'geforcegtx1080',  'nvidiageforcegtx1080'}
                                    useDockerImage = 'digitalprodev/pbrt-v4-gpu-pascal-shared';
                                otherwise
                                    warning('No compatible docker image for GPU model: %s, running on CPU', GPUModel);
                                    obj.gpuRendering = false;
                                    useDockerImage = dockerWrapper.localImage();
                            end
                        else
                            useDockerImage = dockerWrapper.localImage();
                        end
                    elseif isequal(processorType, 'CPU')

                        if obj.localRender
                            % localImage is where we sort out x86 v. ARM
                            useDockerImage = dockerWrapper.localImage;
                        else
                            % remote CPU!!
                            % What if it has a different architecture?
                            useDockerImage = obj.remoteCPUImage;
                        end
                    end
                end
            end
        end

        % Not yet defined.
        %function output = convertPathsInFile(obj, input)
        % for depth or other files that have embedded "wrong" paths
        % implemented someplace, need to find the code!
        %end

        %% Inserted from getRenderer.  thisD is a dockerWrapper (obj)
        function getRenderer(thisD)
            %GETRENDERER uses the 'docker' parameters to insert the
            %renderer
            %
            % Description
            %  The initial dockerWrapper is filled in with the user's
            %  preferences from (getpref('docker')).  This method builds on
            %  those to set a few additional parameters that are
            %  site-specific.
            %
            %  You can adjust the default parameters, which are stored
            %  in the Matlab prefs under 'docker' using the method
            %
            %       dockerWrapper.setPrefs(varargin)
            %
            %  To list the current prefs you can use
            %
            %     dockerWrapper.getPrefs;
            %
            %  VISTALAB GPU Information
            %
            %   The default uses the 3070 on muxreconrt.stanford.edu.
            %   This approach requires having an ssh-key based user
            %   login as described on the wiki page. Specifically,
            %   your username & homedir need to be the same on both
            %   machines.
            %
            % Current GPU Options at vistalab:
            %
            %   muxreconrt:
            %     GPU 0: Nvidia 3070 -- -ampere -- (Broken)
            %     GPU 1: Nvidia 2080 Ti -- -volta -- setpref('docker','whichGPU', 1);
            %     GPU 2: Nvidia 2080 Ti -- -volta -- setpref('docker','whichGPU', 2);
            %
            % Remote CPU:
            %     mux
            %     (gray??)
            %     (black??)
            %
            % See also
            %   dockerWrapper

            if thisD.localRender
                % Running on the user's local machine, whether there is a
                % GPU or not.  The container name is probably in
                % thisD.localImage, or in the software default.

                % This used to be here, but it seemed wrong to BW.
                % thisD.dockerImageName = thisD.localImage;
                return;
            else
                % Rendering on a remote machine.

                % This sets dockerWrapper parameters that were not already
                % set and creates the docker context.

                % Docker doesn't allow use of ~ in volume mounts, so we need to
                % make sure we know the correct remote home dir:
                if ispc
                    % This probably should use the thisD.remoteRoot, not
                    % the getpref() method.
                    thisD.remoteRoot = getpref('docker','remoteRoot',dockerWrapper.pathToLinux(fullfile('/home',getUserName(thisD))));
                end

                if isempty(thisD.remoteMachine)
                    % If the remoteMachine was not set in prefs, we get the
                    % default. The user may have multiple opportunities
                    % for this.  For now we default to the
                    % vistalabDefaultServer.
                    thisD.remoteMachine = thisD.vistalabDefaultServer;
                end

                % We allow one remote render context
                % if the user specifies one, make sure it exists
                % otherwise create one
                thisD.staticVar('set','renderContext', getRenderContext(thisD, thisD.vistalabDefaultServer));

                if isempty(thisD.remoteImage)
                    % If we know the remote machine, but not the remote
                    % image, we try fill in the remote Docker image to
                    % use.  We do this depending on the machine and the
                    % GPU.  A different image is needed for each, sigh.
                    %
                    % BW:  Setting to
                    % 'digitalprodev/pbrt-v4-gpu-ampere-mux:latest' to test
                    % microlens code.  It was empty and defaulted to
                    % 'shared' one below.

                    if isequal(thisD.remoteMachine, thisD.vistalabDefaultServer)
                        switch thisD.whichGPU
                            case {0, -1}
                                thisD.remoteImage = 'digitalprodev/pbrt-v4-gpu-ampere-mux';
                            case 1
                                thisD.remoteImage = 'digitalprodev/pbrt-v4-gpu-volta-mux';
                            case 2
                                thisD.remoteImage = 'digitalprodev/pbrt-v4-gpu-volta-mux';
                        end

                        % If the user specified a different tag for the
                        % docker image, use the one they specified.
                        if ~isempty(thisD.remoteImage) && ~contains(thisD.remoteImage,':') % add tag
                            thisD.remoteImage = [thisD.remoteImage, ':', thisD.remoteImageTag];
                        end
                    else
                        % This seems like a problem to me (BW).
                        warning('Unable to identify the remoteImage');
                    end
                end
            end

        end

        function userName = getUserName(obj)
            % Reads the user name from a docker wrapper object, or from the
            % system and then sets it in the docker wrapper object.

            % Different methods are needed for different systems.
            if ~isempty(obj.remoteUser)
                % Maybe it is already present in the object
                userName = obj.remoteUser;
                return;
            elseif ispc
                userName = getenv('username');
            elseif ismac
                [~, paddedName] = system('id -un');
                paddedArray = splitlines(paddedName);
                userName = paddedArray{1};
            elseif isunix
                % depressingly we get a newline at the end:(
                [~, paddedName] = system('whoami');
                paddedArray = splitlines(paddedName);
                userName = paddedArray{1};
            else
                error('Unknown system type.');
            end

            % Set it because we have it now!
            obj.remoteUser = userName;

        end

        % validates rendering context if remote rendering
        % will try to create one if none is available
        function useContext = getRenderContext(obj, serverName)
            if isempty(obj.renderContext)
                ourContext = 'remote-mux';
            else
                ourContext = obj.renderContext;
            end
            % Get or set-up the rendering context for the docker container
            %
            % A docker context ('docker context create ...') is a set of
            % parameters we define to address the remote docker container
            % from our local computer.
            %
            if ~exist('serverName','var'), serverName = obj.remoteMachine; end

            switch serverName
                case obj.vistalabDefaultServer()
                    % Check that the Docker context exists.
                    checkContext = sprintf('docker context list');
                    [status, result] = system(checkContext);

                    if status ~= 0 || ~contains(result,ourContext)
                        % If we do not have it, create it
                        % e.g. ssh://<username>@<server>
                        % use the pref for remote username,
                        % otherwise assume it is the same as our local user
                        if isempty(obj.remoteUser)
                            rUser = getUserName(obj);
                        else
                            rUser = obj.remoteUser;
                        end

                        contextString = sprintf(' --docker host=ssh://%s@%s',...
                            rUser, obj.vistalabDefaultServer);
                        createContext = sprintf('docker context create %s %s',...
                            contextString, ourContext);

                        [status, result] = system(createContext);
                        if status ~= 0 || numel(result) == 0
                            warning("Failed to create context: %s -- Might already exist.\n",ourContext);
                            disp(result)
                        else
                            fprintf("Created docker context %s for Vistalab server\n",ourContext);
                        end
                    end
                    useContext = 'remote-mux';
                otherwise
                    % User is on their own to make sure they have a valid
                    % context
            end
        end

    end
end



