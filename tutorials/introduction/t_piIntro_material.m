%% Illustrates setting scene materials
%
% This example scene includes glass and other materials.  The script
% sets up the glass material and number of bounces to make the glass
% appear reasonable.
%
% It also uses piMaterialsGroupAssign() to set a list of materials (in
% this case a mirror) that are part of the scene.
%
% Dependencies:
%
%    ISET3d, (ISETCam or ISETBio), JSONio
%
% ZL, BW SCIEN 2018
%
% See also
%   t_piIntro_*

%% Initialize ISET and Docker
clear; close all; ieInit;
if ~piDockerExists, piDockerConfig; end

%% Read pbrt files
sceneName = 'simple scene';
thisR = piRecipeDefault('scene name',sceneName);

%% Set render quality
%
% This is a low resolution for speed.
thisR.set('film resolution',[400 300]);
thisR.set('rays per pixel',64);

%% List material library
%
% These all the possible materials. 
mType = piMateriallib;
disp(mType);
thisR.materials.lib

% These are the materials in this particular scene.
piMaterialList(thisR);

%% Write out the pbrt scene file, based on thisR.
thisR.set('fov',45);
thisR.set('film diagonal',10);
thisR.set('integrator subtype','bdpt');
thisR.set('sampler subtype','sobol');
piWrite(thisR,'creatematerials',true);

%% Render
scene = piRender(thisR);
scene = sceneSet(scene,'name',sprintf('Uber %s',sceneName));
sceneWindow(scene);
sceneSet(scene,'gamma',0.5);

%% Adjust the scene material from uber to mirror
%
% The SimpleScene has a part named 'mirror' (slot 5), but the
% material type is set to uber.  We want to change that.
partName = 'mirror';

% Get the mirror material from the library.  The library is always
% part of any recipe.
target = thisR.materials.lib.mirror; 
piMaterialAssign(thisR, partName, target);

% Set the render to account for glass and mirror requiring multiple bounces
%
% This value determines the number of ray bounces.  If a scene has
% glass we need to have at least 2 bounces.
thisR.set('nbounces',10);

% Write and render
piWrite(thisR,'creatematerials',true);
[scene, result] = piRender(thisR);
scene = sceneSet(scene,'name',sprintf('Glass %s',sceneName));
sceneWindow(scene);
sceneSet(scene,'gamma',0.5);

%% Adjust the scene material from mirror to glass (the person, too)

% Now change the partName 'mirror' to glass material. 
target = thisR.materials.lib.glass; 
piMaterialAssign(thisR, partName, target);
piMaterialAssign(thisR, 'GLASS', target);

% Set the person to glass, too
personName = 'uber_blue';
piMaterialAssign(thisR, personName, target);

% Write and render
piWrite(thisR,'creatematerials',true);
[scene, result] = piRender(thisR);
scene = sceneSet(scene,'name',sprintf('Glass %s',sceneName));
sceneWindow(scene);
sceneSet(scene,'gamma',0.5);
