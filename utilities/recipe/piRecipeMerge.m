function sceneR = piRecipeMerge(sceneR, objectRs, varargin)
% Add multiple object recipes into a base scene recipe
%
% Synopsis:
%   sceneR = piRecipeMerge(sceneR, objects, varargin)
% 
% Brief description:
%   Merges objects information (material, texture, assets) from two recipes
%   into one. 
%
% Inputs:
%   sceneR    - scene recipe
%   objectRs  - a single object recipe or a cell array of object recipes
%   
% Optional key/val pairs
%   material  -  The user can decide to NOT add materials.  Default is true
%                meaning (add)
%   texture   -  Same as material
%   asset     -  Same as material
%   node name -  Top node of the subtree. Default is the node with id = 2.
%   object instance - Probably added by Zhenyi.  Needs a comment.
%
% Returns:
%   sceneR   - scene recipe with added objects
%
% See also
%

%% Parse input
varargin = ieParamFormat(varargin);

p = inputParser;
p.addRequired('sceneR', @(x)isequal(class(x),'recipe'));
p.addRequired('objectRs', @(x)isequal(class(x),'recipe') || iscell);

% So far, we add materials, textures, and assets.  We have not yet
% addressed lights.  The user can 
p.addParameter('material',true);
p.addParameter('texture',true);
p.addParameter('asset',true);
p.addParameter('objectinstance',true);
p.addParameter('nodename','',@ischar);  % Name of the top node in the subtree

p.parse(sceneR, objectRs, varargin{:});

sceneR         = p.Results.sceneR;
materialFlag   = p.Results.material;
textureFlag    = p.Results.texture;
assetFlag      = p.Results.asset;
objectInstance = p.Results.objectinstance;
nodeName       = p.Results.nodename;
copyTextureFlag = 1;
%%  The objects can be a cell or a recipe

if ~iscell(objectRs)
    % Make it a cell
    recipelist{1} = objectRs;
else
    % A cell array of recipes
    recipelist = objectRs;
end

%% For each object recipe, add the object to the main scene

for ii = 1:length(recipelist)
    thisR = recipelist{ii};
    
    if assetFlag
        
        if isempty(sceneR.assets)
            % Main scene has no assets.  Add in the assets from the object.
            % Then we also have to set the nodeName for the return.
            sceneR.assets = thisR.assets;
        else
            if isempty(nodeName)
                % Get the asset names in the object
                % The problem with this is we don't get the geometry node above
                % it.
                %   names = thisR.get('assetnames');
                %   nodeName = names{2};

            end
            children = thisR.assets.getchildren(1);
            % Get the subtree starting just below the specified node
            % thisOBJsubtree = thisR.get('asset', nodeName, 'subtree');
            
            % Graft the asset three into the scene.  We graft it onto the root
            % of the main scene.
            % Changed to root_B on Jan 23, 2022.  Worried (BW).
            % The new field 'isInstancer' broke reading in one of the
            % assets.  I do not understand that field from its name; the
            % comment below has me confused, so I will ask Zhenyi about it.
            % For the moment merging some assets (like the bunny) does not
            % work. (BW)
            for nChild = 1:numel(children)
                thisNodeTree = thisR.get('asset', children(nChild), 'subtree');
                [~,thisNode] = piAssetFind(thisR.assets, 'asset',children(nChild));
                if objectInstance && isfield(thisNode{1},'isInstancer')
                    if thisNode{1}.isInstancer == 1
                        % For an asset tree, we save the parent object and
                        % set isInstancer flag to be 1, when the instance
                        % is called the node's isInstancer flag is 0; In
                        % this case, when we merge the scene, we would like
                        % to only merge the parent object, we will add
                        % instance later using piObjectInstanceCreate.
                        % --Zhenyi
                        sceneR = sceneR.set('asset', 1, 'graft', thisNodeTree);
                    end
                end
            end
        end
        
        % Copy meshes from objects folder to scene folder here
        sourceDir = thisR.get('input dir');
        dstDir    = sceneR.get('output dir');
        
        % Copy the assets from source to destination
        sourceAssets = fullfile(sourceDir, 'scene/PBRT/pbrt-geometry');
        if isfolder(sourceAssets) && ~isempty(dir(fullfile(sourceAssets,'*.pbrt')))
            dstAssets = fullfile(dstDir,    'scene/PBRT/pbrt-geometry');
            copyfile(sourceAssets, dstAssets);
        else
            if isfolder(sourceDir)
                if ~isfolder(dstDir), mkdir(dstDir), end
                piCopyFolder(sourceDir, dstDir);
                copyTextureFlag = 0;
            end
        end
    end
    
    if materialFlag
        % Combines the material lists in the two recipes
        if ~isempty(sceneR.materials)
            sceneR.materials.list = [sceneR.materials.list; thisR.materials.list];
        else
            sceneR.materials = thisR.materials;
        end
    end
    
    if textureFlag
        % Combines the lists in the recipes, and then the files
        if ~isempty(sceneR.textures)
            sceneR.textures.list = [sceneR.textures.list; thisR.textures.list];
        else
            sceneR.textures = thisR.textures;
        end
        if copyTextureFlag
            % Copy texture files
            sourceDir = thisR.get('output dir');
            dstDir    = sceneR.get('output dir');
            sourceTextures = fullfile(sourceDir, 'textures');
            if exist(sourceTextures, 'dir')
                piCopyFolder(sourceTextures, dstDir);
            end
        end
    end
end

end

