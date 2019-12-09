
clear
close all

%% data allocation for linear regression
%  [Xdata_29] = load('data2/data.txt'); % ionosphere dataset
%  [ydata_29] = load('data2/y.txt'); 
% [Xdata_29] = load('data9/data.txt'); % adult dataset
% [ydata_29] = load('data9/y.txt');   
[Xdata_29] = load('data11/data.txt'); % derm dataset
[ydata_29] = load('data11/y.txt');   


num_iter=40000;
accuracy=1E-4;
num_workers=24;
X=cell(num_workers);
y=cell(num_workers);

num_feature=size(Xdata_29(1:50,:),2);
num_sample=size(Xdata_29(1:50,:),1); 
Xdata=randn(num_sample,num_feature);

ydata=[ydata_29(1:50)];

[Q R]=qr(Xdata);
diagmatrix=diag(ones(num_sample,1));
% [lambda]=eig(Xdata'*Xdata);
Hmax=zeros(num_workers,1);
for i=1:num_workers
   X{i}=1^(i-1)*Q(:,i)*Q(:,i)'+diag(ones(num_sample,1));
   Hmax(i)=max(eig(X{i}'*X{i})); 
   y{i}=ydata;
end

num_feature=size(X{1},2);

Hmax_sum=sum(Hmax);

%% data pre-analysis for GD and LAG algorithms that we compare with
lambda=0.001;
lambda=0.00001;

Hmax=zeros(num_workers,1);
for i=1:num_workers
   Hmax(i)=0.25*max(abs(eig(X{i}'*X{i})))+lambda; 
end
Hmax_sum=sum(Hmax);
hfun=Hmax_sum./Hmax;
nonprob=Hmax/Hmax_sum;

Hmin=zeros(num_workers,1);
Hcond=zeros(num_workers,1);
for i=1:num_workers
   Hmin(i)=lambda; 
   Hcond(i)=Hmax(i)/Hmin(i);
end

X_fede=[];
y_fede=[];
for i=1:num_workers
  X_fede=[X_fede;X{i}];
  y_fede=[y_fede;y{i}];
end

triggerslot=10;
Hmaxall=0.25*max(eig(X_fede'*X_fede))+lambda;
[cdff,cdfx] = ecdf(Hmax*num_workers/Hmaxall);
comm_save=0;
for i=1:triggerslot
    comm_save=comm_save+(1/i-1/(i+1))*cdff(find(cdfx>=min(max(cdfx),sqrt(1/(triggerslot*i))),1));
end

heterconst=mean(exp(Hmax/Hmaxall));
heterconst2=mean(Hmax/Hmaxall);
rate=1/(1+sum(Hmin)/(4*sum(Hmax)));
%% parameter initialization
%triggerslot=100;
theta=zeros(num_feature,num_iter);
grads=ones(num_feature,num_workers);
%stepsize=1/(num_workers*max(Hmax));
stepsize=1/Hmaxall;
thrd=10/(stepsize^2*num_workers^2)/triggerslot;
comm_count=ones(num_workers,1);

theta2=zeros(num_feature,num_iter);
grads2=ones(num_feature,1);
stepsize2=stepsize;

theta3=zeros(num_feature,num_iter);
grads3=ones(num_feature,num_workers);
stepsize3=stepsize2/num_workers; % cyclic access learning

theta4=zeros(num_feature,num_iter);
grads4=ones(num_feature,num_workers);
stepsize4=stepsize/num_workers; % nonuniform-random access learning


thrd5=1/(stepsize^2*num_workers^2)/triggerslot;
theta5=zeros(num_feature,1);
grads5=ones(num_feature,num_workers);
stepsize5=stepsize;
comm_count5=ones(num_workers,1);

%thrd6=2/(stepsize*num_workers);
theta6=zeros(num_feature,1);
grads6=ones(num_feature,1);
stepsize6=0.5*stepsize;
comm_count6=ones(num_workers,1);


theta7=zeros(num_feature,1);
grads7=ones(num_feature,num_workers);
stepsize7=stepsize;
comm_count7=ones(num_workers,1);

% lambda=0.000;


%% Optimal solution

XX=X_fede;
YY=y_fede;
%size = num_feature;

obj0 = opt_sol_logistic(XX,YY, num_feature, lambda, num_workers)%(0.5*sum_square(XX*z1 - YY));

opt_obj = obj0*ones(1,num_iter);



%%  GD
comm_error2=[];
comm_grad2=[];
for iter=1:num_iter
    if mod(iter,1000)==0
        iter
    end
    % central server computation
    if iter>1
    grads2=-(X_fede'*(y_fede./(1+exp(y_fede.*(X_fede*theta2(:,iter))))))+num_workers*lambda*theta2(:,iter);
        end
    grad_error2(iter)=norm(sum(grads2,2),2);
    obj_GD(iter)=num_workers*lambda*0.5*norm(theta2(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta2(:,iter)))));
    loss_GD(iter)=abs(num_workers*lambda*0.5*norm(theta2(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta2(:,iter)))))-obj0);
    theta2(:,iter+1)=theta2(:,iter)-stepsize2*grads2;
    %comm_error2=[comm_error2;iter*num_workers,loss2(iter)]; 
    %comm_grad2=[comm_grad2;iter*num_workers,grad_error2(iter)]; 
    if(loss_GD(iter) < accuracy)
        break;
    end
end

obj1 = obj_GD(iter)
% opt_obj = obj0*ones(1,num_iter);
% for iter=1:num_iter
% loss_GD(iter)=abs(num_workers*lambda*0.5*norm(theta2(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta2(:,iter)))))-obj0);
% end
%% LAG-PS
comm_iter=1;
comm_index=zeros(num_workers,num_iter);
comm_error=[];
comm_grad=[];
theta_temp=zeros(num_feature,num_workers);

for iter=1:num_iter
    
    comm_flag=0;
 %   local worker computation
    for i=1:num_workers
        if iter>triggerslot
            trigger=0;
            for n=1:triggerslot
            trigger=trigger+norm(theta(:,iter-(n-1))-theta(:,iter-n),2)^2;
            end

            if Hmax(i)^2*norm(theta_temp(:,i)-theta(:,iter),2)^2>thrd*trigger
                grads(:,i)=-(X{i}'*(y{i}./(1+exp(y{i}.*(X{i}*theta(:,iter))))))+lambda*theta(:,iter);
                theta_temp(:,i)=theta(:,iter);
                comm_index(i,iter)=1;
                comm_count(i)=comm_count(i)+1;
                comm_iter=comm_iter+1;
                comm_flag=1;
            end
        end
    end
    
%    central server computation
    grad_error(iter)=norm(sum(grads,2),2);
    obj_LAG_PS(iter)=num_workers*lambda*0.5*norm(theta(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta(:,iter)))));
    loss_LAG_PS(iter)=abs(num_workers*lambda*0.5*norm(theta(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta(:,iter)))))-obj0);
    theta(:,iter+1)=theta(:,iter)-stepsize*sum(grads,2);
    

    if comm_flag==1
        %comm_error=[comm_error;comm_iter,loss(iter)];
        %comm_grad=[comm_grad;comm_iter,grad_error(iter)];
    elseif  mod(iter,1000)==0
        iter
        comm_iter=comm_iter+1;
        %comm_error=[comm_error;comm_iter,loss(iter)];
        %comm_grad=[comm_grad;comm_iter,grad_error(iter)];
    end
comm_iter_final_LAG_PS(iter)=comm_iter;
if(loss_LAG_PS(iter) < accuracy)
        break;
end
end

%% LAG-WK
comm_iter5=1;
comm_index5=zeros(num_workers,num_iter);
comm_error5=[];
comm_grad5=[];
for iter=1:num_iter

    comm_flag=0;
    % local worker computation
    for i=1:num_workers
        grad_temp=-(X{i}'*(y{i}./(1+exp(y{i}.*(X{i}*theta5(:,iter))))))+lambda*theta5(:,iter);
        if iter>triggerslot
            trigger=0;
            for n=1:triggerslot
            trigger=trigger+norm(theta5(:,iter-(n-1))-theta5(:,iter-n),2)^2;
            end

            if norm(grad_temp-grads5(:,i),2)^2>thrd5*trigger
                grads5(:,i)=grad_temp;
                comm_count5(i)=comm_count5(i)+1;
                comm_index5(i,iter)=1;
                comm_iter5=comm_iter5+1;
                comm_flag=1;
            end
        end       
    end
    grad_error5(iter)=norm(sum(grads5,2),2);
    obj_LAG_WK(iter)=num_workers*lambda*0.5*norm(theta5(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta5(:,iter)))));
    loss_LAG_WK(iter)=abs(num_workers*lambda*0.5*norm(theta5(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta5(:,iter)))))-obj0);
    if comm_flag==1
       %comm_error5=[comm_error5;comm_iter5,loss5(iter)]; 
       %comm_grad5=[comm_grad5;comm_iter5,grad_error5(iter)]; 
    elseif  mod(iter,1000)==0
        iter
        comm_iter5=comm_iter5+1; 
        %comm_error5=[comm_error5;comm_iter5,loss5(iter)]; 
       %comm_grad5=[comm_grad5;comm_iter5,grad_error5(iter)]; 
    end
    theta5(:,iter+1)=theta5(:,iter)-stepsize5*sum(grads5,2);
comm_iter_final_LAG_WK(iter) = comm_iter5;
if(loss_LAG_WK(iter) < accuracy)
        break;
end
end

%% cyclic IAG
for iter=1:num_iter
    if mod(iter,100)==0
        iter
    end
    if iter>1
    % local worker computation
    i=mod(iter,num_workers)+1;
    grads3(:,i)=-(X{i}'*(y{i}./(1+exp(y{i}.*(X{i}*theta3(:,iter))))))+lambda*theta3(:,iter);
    end
    % central server computation
    grad_error3(iter)=norm(sum(grads3,2),2);
    obj_cyclic_IAG(iter)=num_workers*lambda*0.5*norm(theta3(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta3(:,iter)))));
    loss_cyclic_IAG(iter)=abs(num_workers*lambda*0.5*norm(theta3(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta3(:,iter)))))-obj0);
    theta3(:,iter+1)=theta3(:,iter)-stepsize3*sum(grads3,2);
    if(loss_cyclic_IAG(iter) < accuracy)
        break;
    end
end

%% non-uniform RANDOMIZED IAG
for iter=1:num_iter
    if mod(iter,100)==0
        iter
    end
    % local worker computation
    workprob=rand;
    for i=1:num_workers
        if workprob<=sum(nonprob(1:i));
           break;
        end
    end
    %i=randi(num_workers);   
    if iter>1
    grads4(:,i)=-(X{i}'*(y{i}./(1+exp(y{i}.*(X{i}*theta4(:,iter))))))+lambda*theta4(:,iter);
    end
    % central server computation
    grad_error4(iter)=norm(sum(grads4,2),2);
    obj_R_IAG(iter)=num_workers*lambda*0.5*norm(theta4(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta4(:,iter)))));
    loss_R_IAG(iter)=abs(num_workers*lambda*0.5*norm(theta4(:,iter))^2+sum(log(1+exp(-y_fede.*(X_fede*theta4(:,iter)))))-obj0);
    theta4(:,iter+1)=theta4(:,iter)-stepsize4*sum(grads4,2);
    if(loss_R_IAG(iter) < accuracy)
        break;
    end
    
end

%% GADMM

num_iter=400;

acc = accuracy;%1E-3;
rho=0.0003;
[obj_GADMM_rho0003, loss_GADMM_rho0003, Iter_0003] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
rho

rho=0.0005;
[obj_GADMM_rho0005, loss_GADMM_rho0005, Iter_0005] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
rho

rho=0.0007;
[obj_GADMM_rho0007, loss_GADMM_rho0007, Iter_0007] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
rho

rho=0.0009;
[obj_GADMM_rho0009, loss_GADMM_rho0009, Iter_0009] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
rho

% rho=0.03;
% [obj_GADMM_rho3, loss_GADMM_rho3, Iter_3] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
% rho
% 
% rho=0.05;
% [obj_GADMM_rho5, loss_GADMM_rho5, Iter_5] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
% rho
% 
% rho=0.07;
% [obj_GADMM_rho7, loss_GADMM_rho7, Iter_7] = group_ADMM_logistic(X_fede,y_fede, rho, num_workers, num_feature, num_sample, num_iter, obj0, lambda, acc);
% rho


num_iter = 40000;

for iter=1:num_iter
    cumulative_com_GD(iter)=iter*num_workers+iter; 
    %errorPer_GD(iter) = abs(loss_GD(iter)/opt_obj(iter)*100);        
end

for iter=1:length(comm_iter_final_LAG_PS)
    cumulative_com_LAG_PS(iter)=comm_iter_final_LAG_PS(iter)+iter;  
    %errorPer_LAG_PS(iter) = abs(loss_LAG_PS(iter)/opt_obj(iter)*100);        
end

for iter=1:length(comm_iter_final_LAG_WK)
    cumulative_com_LAG_WK(iter)=comm_iter_final_LAG_WK(iter)+iter;  
    %errorPer_LAG_WK(iter) = abs(loss_LAG_WK(iter)/opt_obj(iter)*100);        
end

num_iter=Iter_0005;
for iter=1:num_iter
    cumulative_com_GADMM_rho0005(iter)=iter*num_workers;   
    %errorPer_GADMM_rho3(iter) = abs(loss_GADMM_rho3(iter)/opt_obj(iter)*100);        
end

num_iter=Iter_0007;
for iter=1:num_iter
    cumulative_com_GADMM_rho0007(iter)=iter*num_workers;   
    %errorPer_GADMM_rho5(iter) = abs(loss_GADMM_rho5(iter)/opt_obj(iter)*100);        
end

num_iter=Iter_0009;
for iter=1:num_iter
    cumulative_com_GADMM_rho0009(iter)=iter*num_workers;   
    %errorPer_GADMM_rho7(iter) = abs(loss_GADMM_rho7(iter)/opt_obj(iter)*100);        
end


% save logReg_24Users_syntheticData.mat obj_GD obj_cyclic_IAG obj_R_IAG obj_LAG_PS obj_LAG_WK...
%     loss_GD loss_cyclic_IAG loss_R_IAG loss_LAG_PS loss_LAG_WK opt_obj...
%     obj_GADMM_rho0005 loss_GADMM_rho0005 obj_GADMM_rho0007 loss_GADMM_rho0007...
%     obj_GADMM_rho0009 loss_GADMM_rho0009

figure(2);
subplot(1,2,1);
semilogy(loss_GD,'r-','LineWidth',3);
hold on
semilogy(loss_cyclic_IAG,'c-','LineWidth',3);
hold on
semilogy(loss_R_IAG,'g--','LineWidth',3);
hold on
semilogy(loss_LAG_PS,'r--','LineWidth',3);
hold on
semilogy(loss_LAG_WK,'m-','LineWidth',3);
hold on
semilogy(loss_GADMM_rho0005,'k-','LineWidth',3);
hold on
semilogy(loss_GADMM_rho0007,'k--','LineWidth',3);
hold on
semilogy(loss_GADMM_rho0009,'b--','LineWidth',3);
hold on
% semilogy(loss_GADMM_rho3,'r--','LineWidth',3);
% hold on
% semilogy(loss_GADMM_rho5,'k-','LineWidth',3);
% hold on
% % semilogy(loss_GADMM_rho6,'r--','LineWidth',3);
% % hold on
% 
% semilogy(loss_GADMM_rho7,'b--','LineWidth',3);
% hold on

xlabel({'Number of Iterations';'(a)'},'fontsize',16,'fontname','Times New Roman')
ylabel('Objective Error','fontsize',16,'fontname','Times New Roman')
legend('GD','cyclic-IAG','R-IAG','LAG-PS','LAG-WK','GADMM, \rho=5E-4'...
    ,'GADMM, \rho=7E-4','GADMM, \rho=9E-4');%,'Batch-GD')
%ylim([10^-4 10^3])
%xlim([10 30000])

set(gca,'fontsize',14,'fontweight','bold');



subplot(1,2,2);
semilogy(cumulative_com_GD(1:length(loss_GD)), loss_GD,'r-','LineWidth',3);
hold on
semilogy(cumulative_com_LAG_PS, loss_LAG_PS,'r--','LineWidth',3);
hold on
semilogy(cumulative_com_LAG_WK, loss_LAG_WK,'m-','LineWidth',3);
hold on
semilogy(cumulative_com_GADMM_rho0005,loss_GADMM_rho0005, 'k-','LineWidth',3);
hold on
semilogy(cumulative_com_GADMM_rho0007,loss_GADMM_rho0007, 'k--','LineWidth',3);
hold on
semilogy(cumulative_com_GADMM_rho0009,loss_GADMM_rho0009, 'b--','LineWidth',3);
hold on



xlabel({'Cumulative Communication Cost';'(b)'},'fontsize',16,'fontname','Times New Roman')
ylabel('Objective Error','fontsize',16,'fontname','Times New Roman')
legend('GD','LAG-PS','LAG-WK','GADMM, \rho=5E-4'...
    ,'GADMM, \rho=7E-4','GADMM, \rho=9E-4');%,'Batch-GD')
%ylim([10^-4 10^3])
%xlim([200 100000])
set(gca,'fontsize',14,'fontweight','bold');

figure(4);

semilogy(loss_GADMM_rho0005,'k-','LineWidth',3);
hold on
semilogy(loss_GADMM_rho0007,'k--','LineWidth',3);
hold on
semilogy(loss_GADMM_rho0009,'b--','LineWidth',3);
ylim([10^-4 10^2])
xlim([1 63])
set(gca,'fontsize',14,'fontweight','bold');


figure(5);
%semilogy(cumulative_com_LAG_WK, loss_LAG_WK,'m-','LineWidth',3);
%hold on
semilogy(cumulative_com_GADMM_rho0005,loss_GADMM_rho0005, 'k-','LineWidth',3);
hold on
semilogy(cumulative_com_GADMM_rho0007,loss_GADMM_rho0007, 'k--','LineWidth',3);
hold on
semilogy(cumulative_com_GADMM_rho0009,loss_GADMM_rho0009, 'b--','LineWidth',3);
hold on
ylim([10^-4 10^2])
xlim([1 1500])
set(gca,'fontsize',14,'fontweight','bold');
