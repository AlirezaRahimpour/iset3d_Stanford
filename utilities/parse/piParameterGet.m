function value = piParameterGet(thisLine, match)

%{
thisLine = 'AreaLightSource "diffuse" "integer nsamples" [ 16 ] "bool twosided" "true" "rgb L" [ 7.39489317 7.35641623 7.32100344 ]';
value = piParameterGet(thisLine, 'bool twosided')
%}
if strcmp(match, 'L')
    match = ' L';
end
value=[];
if piContains(match,'string') || piContains(match,'bool')
    matchIndex = regexp(thisLine, match);
    if isempty(matchIndex)
        return; 
    end
    newline = thisLine(matchIndex+length(match)+2 : end);
    parameter_toc = regexp(newline, '"');
    value = newline(parameter_toc(1)+1: parameter_toc(2)-1);
elseif piContains(thisLine, '.spd')
    matchIndex = regexp(thisLine, '.spd');
    n=matchIndex;
    while n<numel(thisLine)
        if strcmp(thisLine(n),'"')
            % find spd file end token
            end_toc = n;
            break;
            
        end
        n=n+1;
    end
    n=matchIndex;
    while n>1
        if strcmp(thisLine(n),'"')
            % find spd file end token
            start_toc = n;
            break;
        end
        n=n-1;
    end
    value = thisLine(start_toc+1: end_toc-1);
else
    matchIndex = regexp(thisLine, match);
    if isempty(matchIndex), return;end
    newline = thisLine(matchIndex+length(match)+2 : end);
    quote_toc = regexp(newline, '"');
    if isempty(quote_toc)
        end_toc = numel(newline);
    else
        end_toc = quote_toc-1;
    end
    % get rid of squre brackets
    value = newline(1: end_toc(1));
    value = str2num(value);
end
end