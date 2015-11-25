function [sysr, s0] = cirka(sys, s0, Opts) 

    %% Define execution options
    Def.qm0     = length(s0)+2;
    Def.s0m     = zeros(1,Def.qm0); 
    Def.maxiter = 8; Def.tol = 1e-3;
    Def.verbose = 0; Def.plot = 0;
    Def.updateModel = 'new';
    Def.irka.stopCrit = 's0';
    Def.irka.suppressverbose = 1;
%     Def.irka.maxiter = 20;
%     Def.irka.tol = 1e-2; 

    if ~exist('Opts','var') || isempty(Opts)
        Opts = Def;
    else
        Opts = parseOpts(Opts,Def);
    end 
    
    %% run computations
    stop = 0;
    kIter = 0;
    
    %   Generate the model function
    s0m = Opts.s0m;    [sysm, s0mTot, V, W] = modelFct(sys,s0m);

    if Opts.verbose, fprintf('Starting model function MOR...\n'); end

    while ~stop
        kIter = kIter + 1; if Opts.verbose, fprintf(sprintf('modelFctMor: k=%i\n',kIter));end
        if kIter > 1
            % update model
            [sysm, s0mTot, V, W] = modelFct(sys,s0,s0mTot,V,W,Opts);
        end
        % reduction of new model with new starting shifts
        [sysr, ~,~, s0new] = irka(sysm,s0,Opts.irka);
        % computation of convergence
        if stoppingCrit
            stop = 1;
        else
            %Overwrite parameters with new variables
            s0 = s0new;    
        end
        if kIter > Opts.maxiter; 
            warning('modelFctMor did not converge within maxiter'); 
            return
        end
    end

    function stop = stoppingCrit
        stop = 0;
        if norm(s0) == 0
            crit = norm(setdiffVec(s0new,s0)); %absolute
        else
            crit = norm(setdiffVec(s0new,s0))/norm(s0); %relative
        end
        if crit <= Opts.tol, stop = 1;
        elseif length(s0mTot)> size(sys.a,1),stop = 1;end
    end    
end