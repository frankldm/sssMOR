function [sysr, s0new] = modelFctMor(sys,redFct,varargin)
% MODELFCTMOR - model function-based model order reduction
%
% Syntax:
%   MODELFCTMOR(sys,redFct)
%   MODELFCTMOR(sys,redFct,s0)
%   MODELFCTMOR(sys,redFct,Opts)
%   MODELFCTMOR(sys,redFct,s0,Opts)
%   sysr = MODELFCTMOR(sys,redFct)
%   [sysr, s0] = MODELFCTMOR(sys,redFct)
%
% Description:
%   This function executes the reduction scheme defined by the handle 
%   redFct, by generating a model function that substitues the original
%   model sys. This substitution saves execution time. 
%   Upon convergence, the model function is updated and the reduction is
%   conducted again until convergence of the overall scheme.
%
%   redFct is a function handle that is given
%       - a dynamical system sys
%       - a set of shifts s0
%   and returns:
%       - a reduced order dynamical system sysr
%       - a new set of (optimal) shifts
%
% See also:
%   IRKA, CURE, SPARK
%
% References:
%   [1] Castagnotto (2015), tbd
%
% ------------------------------------------------------------------
%   This file is part of sssMOR, a Sparse State Space, Model Order
%   Reduction and System Analysis Toolbox developed at the Institute 
%   of Automatic Control, Technische Universitaet Muenchen.
%   For updates and further information please visit www.rt.mw.tum.de
%   For any suggestions, submission and/or bug reports, mail us at
%                     -> sssMOR@rt.mw.tum.de <-
% ------------------------------------------------------------------
% Authors:      Alessandro Castagnotto
% Last Change:  01 Sep 2015
% Copyright (c) 2015 Chair of Automatic Control, TU Muenchen
% ------------------------------------------------------------------

    %%  Input parsing
    %   Varargin
    if nargin > 2
        if ~isstruct(varargin{1})
            s0 = varargin{1};
            if nargin == 4
                Opts = varargin{2};
            end
        else
            s0 = [];
            Opts = varargin{1};
        end
    end

    %   Default Opts
    Def.qm0     = max([10,2*length(s0)]); %at least twice the reduced order
    Def.s0m     = zeros(1,Def.qm0);
    Def.maxiter = 20;
    Def.tol     = 1e-6;
    Def.verbose = 0;

    if ~exist('Opts','var') || isempty(Opts)
        Opts = Def;
    else
        Opts = parseOpts(Opts,Def);
    end  
    %%  Computations
    %   Initialize variables in nested functions
    L1 = zeros(size(sys.A));U1=L1;P1=L1;Q1=L1; 
    L2 = zeros(size(sys.A));U2=L2;P2=L2;Q2=L2; 
    
    %   Initialize model function
    s0m = Opts.s0m; 
    V = []; W = []; [sysm,V,W] = buildModelFunction(s0m,V,W);
   
    stop = 0;
    kIter = 0;

    if Opts.verbose, fprintf('Starting model function MOR...\n'); end

    while ~stop
        kIter = kIter + 1; if Opts.verbose, fprintf(sprintf('modelFctMor: k=%i\n',kIter));end
        if kIter > 1
            % update model
            if length(s0m)<size(sys.a,1)
                %   Update model function
                [sysm,V,W] = buildModelFunction(s0,V,W);
            else
                warning(['Model function is already as big as the original model.',...
                    ' Using the original model for one last iteration']);
                sysm = sys;
            end
        end
        % reduction of new model with new starting shifts
        [sysr, s0new] = redFct(sysm,s0);
        % computation of convergence
        if stoppingCrit
            stop = 1;
        else
            s0m = [s0m,s0new]; %shifts for updated model
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
        elseif length(s0m)> size(sys.a,1),stop = 1;end
    end
    
    %%  Model function creation and update
    function [sysm,V,W] = buildModelFunction(s0,V,W)
        idxComplex=find(imag(s0));
        if ~isempty(idxComplex)
            s0c = cplxpair(s0(idxComplex));
            s0(idxComplex) = []; %real shifts
            s0 = [s0 s0c(1:2:end)]; %add 1 complex shift per complex partner
        end

        for iShift = 1:length(s0)
            if iShift > 1 && s0(iShift)==s0(iShift-1)
                    %do nothing: no new LU decomposition needed
            else %new LU needed
                computeLU(s0(iShift));
            end
            V = newColV(V);  W = newColW(W);
        end
        sysm = sss(W'*sys.A*V,W'*sys.B,sys.C*V,...
                            zeros(size(sys.C,1),size(sys.B,2)),W'*sys.E*V);
    end
    %%  Functions copied from "spark"
    function computeLU(s0)
        % compute new LU decompositions
        if imag(s0)  % complex conjugated 
            [L1,U1,P1,Q1] = lu(sparse(sys.A-s0*sys.E));  L2=conj(L1);U2=conj(U1);P2=P1;Q2=Q1;
        else % real shift
            [L1,U1,P1,Q1] = lu(sparse(sys.A-s0*sys.E)); L2 =[];%make empty
        end
    end
    function V = newColV(V)
        % add columns to input Krylov subspace
        iCol=size(V,2)+1;
        if iCol==1, x = sys.B; else x=sys.E*V(:,iCol-1);end
        r1  = Q1*(U1\(L1\(P1*x)));   
        if isempty(L2) %only one shift 
            v1 = r1;
            V = GramSchmidt([V,v1],[],[],iCol*[1 1]);
        else %complex conjugated pair
            tmp = Q2*(U2\(L2\(P2*x)));
            v1 = real(0.5*r1 + 0.5*tmp); v2  = real(Q2*(U2\(L2\(P2*(sys.E*r1)))));
            V = GramSchmidt([V,v1,v2],[],[],[iCol,iCol+1]);
        end
    end
    function W = newColW(W)
        % add columns to output Krylov subspace
        iCol=size(W,2)+1;
        if iCol==1, x=sys.C; else x=W(:,iCol-1)'*sys.E; end
        l1  = x*Q1/U1/L1*P1;          
        if isempty(L2) %only one shift
            w1 = l1;
            W = GramSchmidt([W,w1'],[],[],iCol*[1 1]);
        else %complex conjugated pair
            tmp = x*Q2/U2/L2*P2;
            w1 = real(0.5*l1 + 0.5*tmp);  w2  = real(l1*sys.E*Q2/U2/L2*P2);
            W = GramSchmidt([W,w1',w2'],[],[],[iCol,iCol+1]);
        end
    end
    function [X,Y,Z] = GramSchmidt(X,Y,Z,cols)
        % Gram-Schmidt orthonormalization
        %   Input:  X,[Y,[Z]]:  matrices in Sylvester eq.: V,S_V,Crt or W.',S_W.',Brt.'
        %           cols:       2-dim. vector: number of first and last column to be treated
        %   Output: X,[Y,[Z]]:  solution of Sylvester eq. with X.'*X = I
        % $\MatlabCopyright$

        if nargin<4, cols=[1 size(X,2)]; end
        
        for kNewCols=cols(1):cols(2)
            for jCols=1:(kNewCols-1)                       % orthogonalization
                T = eye(size(X,2)); T(jCols,kNewCols)=-X(:,kNewCols)'*X(:,jCols);
                X = X*T;
                if nargout>=2, Y=T\Y*T; end
                if nargout>=3, Z=Z*T; end
            end
            h = norm(X(:,kNewCols));  X(:,kNewCols)=X(:,kNewCols)/h; % normalization
            if nargout>=2, Y(:,kNewCols) = Y(:,kNewCols)/h; Y(kNewCols,:) = Y(kNewCols,:)*h; end
            if nargout==3, Z(:,kNewCols) = Z(:,kNewCols)/h; end
        end
    end

%% -------- old    
%     function computeLU(s0)
%         % compute new LU decompositions
%         if real(s0(1))==real(s0(2))  % complex conjugated or double shift
%             [L1,U1,P1,Q1] = lu(sparse(sys.A-s0(1)*sys.E));  L2=conj(L1);U2=conj(U1);P2=P1;Q2=Q1;
%         else                         % two real shifts
%             [L1,U1,P1,Q1] = lu(sparse(sys.A-s0(1)*sys.E));  [L2,U2,P2,Q2] = lu(sparse(sys.A-s0(2)*sys.E));
%         end
%     end
%     function V = newColV(V, k)
%         % add columns to input Krylov subspace
%         for i=(size(V,2)+1):2:(size(V,2)+2*k)
%             if i==1, x=sys.B; else x=sys.E*V(:,i-1); end
%             r1  = Q1*(U1\(L1\(P1*x)));   tmp = Q2*(U2\(L2\(P2*x)));
%             v1 = real(0.5*r1 + 0.5*tmp); v2  = real(Q2*(U2\(L2\(P2*(sys.E*r1)))));
%             V = GramSchmidt([V,v1,v2],[],[],[i,i+1]);
%         end
%     end
%     function W = newColW(W, k)
%         % add columns to output Krylov subspace
%         for i=(size(W,2)+1):2:(size(W,2)+2*k)
%             if i==1, x=sys.C; else x=W(:,i-1)'*sys.E; end
%             l1  = x*Q1/U1/L1*P1;          tmp = x*Q2/U2/L2*P2;
%             w1 = real(0.5*l1 + 0.5*tmp);  w2  = real(l1*sys.E*Q2/U2/L2*P2);
%             W = GramSchmidt([W,w1',w2'],[],[],[i,i+1]);
%         end
%     end
%     function [X,Y,Z] = GramSchmidt(X,Y,Z,cols)
%         % Gram-Schmidt orthonormalization
%         %   Input:  X,[Y,[Z]]:  matrices in Sylvester eq.: V,S_V,Crt or W.',S_W.',Brt.'
%         %           cols:       2-dim. vector: number of first and last column to be treated
%         %   Output: X,[Y,[Z]]:  solution of Sylvester eq. with X.'*X = I
%         % $\MatlabCopyright$
% 
%         if nargin<4, cols=[1 size(X,2)]; end
%         for k=cols(1):cols(2)
%             for j=1:(k-1)                       % orthogonalization
%                 T = eye(size(X,2)); T(j,k)=-X(:,k)'*X(:,j);
%                 X = X*T;
%                 if nargout>=2, Y=T\Y*T; end
%                 if nargout>=3, Z=Z*T; end
%             end
%             h = norm(X(:,k));  X(:,k)=X(:,k)/h; % normalization
%             if nargout>=2, Y(:,k) = Y(:,k)/h; Y(k,:) = Y(k,:)*h; end
%             if nargout==3, Z(:,k) = Z(:,k)/h; end
%         end
%     end
end