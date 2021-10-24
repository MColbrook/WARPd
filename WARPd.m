function [x_final, y_final, all_iterations, err_iterations] = WARPd(opA, epsilon, proxJ, b, x0, y0, delta, n_iter, k_iter, options)
% INPUTS
% ---------------------------
% opA (function handle)     - The sampling operator. opA(x,1) is the forward transform, and opA(y,0) is the adjoint.
% epsilon (double)          - The epsilon parameter in the BP problem.
% proxJ (function handle)   - The proximal operator of J.
% b (vector)                - Measurement vector.
% x0 (vector)               - Initial guess of x.
% x0 (vector)               - Initial guess of dual vector.
% delta (double)            - Algorithm parameter.
% n_iter (int)              - Number of outer iterations.
% k_iter (int)              - Number of inner iterations.
% options                   - Additional options:
%                               .store tells the algorithm whether to store all the iterations
%                               .type is the type of output (1 is non-ergodic for primal and dual,
%                               2 is ergodic for primal and non-ergodic for dual,
%                               3 is non-ergodic for primal and ergodic for dual,
%                               4 is ergodic for primal and dual, 5 is plain PD iterations).
%                               .C1 and .C2 are constants in the inequality in the paper.
%                               .upsilon is the algorithmic parameter (optimal is exp(-1))
%                               .L_A is an upper bound on the norm of A.
%                               .upsilon the rate in the algorithm (optimal is typically exp(-1))
%                               .tau is the proximal step size
%                               .display = 1 displays progress of each call to InnerIt, 0 surpresses this output
%                               .errFcn is an error function computed at each iteration
%                               .opB operator B for l1 analysis term, this also needs op.q (dim of range of op.B)
%
% OUTPUTS
% -------------------------
% x_final (vector)          - Reconstructed vector (primal).
% y_final (vector)          - Reconstructed vector (dual).
% all_iterations (cell)     - If options.store = 1, this is a cell array with all the iterates, otherwise it is an empty cell array
% err_iterations            - If options.errFcn is given, this is a cell array with all the error function computed for the iterates, otherwise it is an empty cell array
    
    
    % add the matrix B if supplied to form joint matrix
    if isfield(options,'opB')
        q=options.q;
        opK = @(x,mode) LINFUN(opA,options.opB,q,x,mode);
        b=[b(:);zeros(q,1)];
    else
        q=0;
        opK=opA;
    end
    
    % set default parameters if these are not given
    if ~isfield(options,'store')
        options.store=0;
    end
    
    if ~isfield(options,'type')
        options.type=1;
    end
    
    if ~isfield(options,'upsilon')
        options.upsilon=exp(-1);
    end
    
    if ~isfield(options,'tau')
        options.tau=1;
    end
    
    if ~isfield(options,'display')
        options.display=1;
    end
    
    if ~isfield(options,'L_A')
        fprintf('Computing the norm of K... ');
        l=rand(length(x0),1);
        l=l/norm(l);
        options.L_A = 1;
        for j=1:10 % perform power iterations
            l2=opK(opK(l,1),0);
            options.L_A=1.01*sqrt(norm(l2));
            l=l2/norm(l2);
        end
        fprintf('upper bound is %d\n',options.L_A);
    end
    
    % rescale everything
    SCALE=norm(b(:),2);
    b=b/SCALE;
    x0=x0/SCALE;
    y0=y0/SCALE;
    epsilon=epsilon/SCALE;
    delta=delta/SCALE;
    options.SCALE=SCALE;

    psi = x0;
    y = y0;
    eps = options.C2*norm(b(:),2);%+norm(x0(:).*weights(:),1);
    all_iterations = cell([n_iter,1]);
    err_iterations = [];
    
    % perform the inner iterations
    fprintf('Performing the inner iterations...\n');
    for j = 1:n_iter
        fprintf('n=%d Progress: ',j);
%         beta=options.C1*(delta+eps)/(sqrt(options.C2^2+q)*k_iter);
        beta=options.C1*(delta+eps)/(sqrt(options.C2^2+q)*ceil(2*options.C1*sqrt(options.C2^2+q)*options.L_A/(options.tau*options.upsilon)));
        al = 1/(beta*k_iter);
        al=min(al,10^12);
        if options.type==5
            options.type=4;
            al=1;
        end
        
        
        [psi_out, y_out, cell_inner_it, err_inner_it] = InnerIt(al*b, al*psi, opK, k_iter, options.tau/options.L_A, options.tau/options.L_A, al*epsilon, proxJ, al, y, options, q);

        for jj=1:length(cell_inner_it)
            cell_inner_it{jj}=cell_inner_it{jj}*SCALE;
        end
        psi = psi_out/al;
        y = y_out;
        all_iterations{j} = cell_inner_it;
        if isfield(options,'errFcn')
            err_iterations = [err_iterations(:);
                                err_inner_it(:)];
        end
        eps = options.upsilon*(delta + eps);
    end

    x_final = psi*SCALE;
    y_final = y*SCALE;

end


function [x_out, y_out, all_iterations, err_iterations]  = InnerIt(b, x0, opK, k_iter, tau1, tau2, epsilon, proxJ, al, y0, options, q)

    xk = x0;
    yk = y0;
    x_sum = zeros(size(xk));
    y_sum = zeros(size(yk));
    all_iterations = cell([k_iter,1]);
    err_iterations = [];
    if isfield(options,'errFcn')
        err_iterations = zeros(k_iter,1);
    end
    
    if options.display==1
        pf = parfor_progress(k_iter);
        pfcleanup = onCleanup(@() delete(pf));
    end

    for k = 1:k_iter

        xkk = proxJ(xk - tau1*opK(yk, 0), tau1);
        ykk = prox_dual( yk + tau2*opK(2*xkk - xk , 1) - tau2*b ,tau2*epsilon, q);

        x_sum = x_sum + xkk;
        y_sum = y_sum + ykk;

        if  options.store==1
            if mod(options.type,2)==0
                all_iterations{k} = x_sum/(al*k);
            else
                all_iterations{k} = xkk/al;
            end
        end
        
        if isfield(options,'errFcn')
            if mod(options.type,2)==0
                err_iterations(k) = options.errFcn(options.SCALE*x_sum/(al*k));
            else
                err_iterations(k) = options.errFcn(options.SCALE*xkk/al);
            end
        end

        xk = xkk;
        yk = ykk;
        
        if options.display==1
            parfor_progress(pf);
        end

    end
    if options.type==1
        x_out = xk;
        y_out = yk;
    elseif options.type==2
        x_out = x_sum/k_iter;
        y_out = yk;
    elseif options.type==3
        x_out = xk;
        y_out = y_sum/k_iter;
    else
        x_out = x_sum/k_iter;
        y_out = y_sum/k_iter;
    end

end

function y_out = prox_dual(y,rho,q)
    y=y(:);
    if q==0
        n_y = norm(y(:),2) + 1e-43;
        y_out = max(0,1-rho/n_y)*y;
    else
        n_y = norm(y(1:(end-q)),2) + 1e-43;
        y_out1 = max(0,1-rho/n_y)*y(1:(end-q));
        y_out2 = min(ones(q,1),1./(abs(y((end-q+1):end))+1e-43)).*y((end-q+1):end);
        y_out=[y_out1; y_out2];
    end
end

function y_out = LINFUN(opA,opB,q,x,mode)
    if mode==1
        y_out=[opA(x,1); opB(x,1)];
    else
        y_out=opA(x(1:(end-q)),0)+opB(x((end-q+1):end),0);
    end
end



