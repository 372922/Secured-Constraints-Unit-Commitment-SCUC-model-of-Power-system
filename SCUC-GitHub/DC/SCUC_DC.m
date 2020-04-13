%SCUC������ֱ����������
clc;
clear;
close all;
clear all class;

addpath('../example');
addpath('../function');

alltime = tic;
tic
%%
% ����
% casename = input('Please enter case name : ', 's');
casename = 'case14mod_SCUC';
% casename = 'case30mod';
% casename = 'IEEE118_new';
k_safe = 0.95;          %��ȫϵ����������һ����ԣ�ȣ���Գ�����ȫԼ��

% ʱ����t ���ڻ�������Ż�
n_T = 24;
% ��������� ���κ��� �ֶ����Ի�
n_L = 20;

% ��ʼ���ļ�
initial;
PD = bus(:, BUS_PD)/baseMVA;
QD = bus(:, BUS_QD)/baseMVA;
% PD = PD*ones(1, n_T);
% QD = QD*ones(1, n_T);
% 24Сʱ�ĸ�������
Q_factor = QD/sum(QD);
P_factor = PD/sum(PD);
%P_sum = sum(PD)-sum(PD)/2*sin(pi/12*[0:n_T-1]+pi/3);
P_sum = mpc.PD'/baseMVA;
QD = Q_factor*sum(QD)*P_sum/sum(PD);
PD = P_factor*P_sum;
spnningReserve = 1.02*P_sum;

%%
%���ɾ������
% [Ybus, Yf, Yt] = makeYbus(baseMVA, bus, M_branch);   % build admitance matrix
[Bbus, Bf, Pbusinj, Pfinj] = makeBdc(baseMVA, bus, branch);       %ֱ������
%%
% �������߱���
% ��������� �Ƿ�����ڵ�ȡ0
gen_P = sdpvar(n_bus, n_T);
gen_P_upper = sdpvar(n_bus, n_T);   %������й������Ͻ�
% gen_Q = sdpvar(n_bus, n_T);
% ���ڵ��ѹ��ֵ ���
% Vm = sdpvar(n_bus, n_T);      %��ֵ
Vm = ones(n_bus, n_T);        %��ֵ ֱ������
Va = sdpvar(n_bus, n_T);      %���

% ��֧·����
PF_D = sdpvar(n_branch, n_T);     %P Flow Direct �����й����� 1->2
% QF_D = sdpvar(n_M_branch, n_T);     %Q Flow Direct �����޹����� 1->2
% PF_R = sdpvar(n_branch, n_T);     %P Flow Reverse �����й����� 2->1
% QF_R = sdpvar(n_M_branch, n_T);     %Q Flow Reverse �����޹����� 2->1

% ����״̬
u_state = binvar(n_bus, n_T);     %��ĸ�������Ƿ�����ڵ�ȡ0
C = [];     %Լ��
% C = sdpvar(C)>=0;

%%
%������������� ���κ����ֶ����Ի�
P_nl = sdpvar(n_gen, n_L, n_T);
for i = 1: n_gen
    for t = 1: n_T
        C = [C,
            gen_P(gen(i,GEN_BUS),t) == sum(P_nl(i,:,t))+gen(i,GEN_PMIN)*u_state(gen(i,GEN_BUS),t)/baseMVA,
            ];
        for l = 1: n_L
            C = [C,
                0 <= P_nl(i,l,t) <= (gen(i, GEN_PMAX)-gen(i, GEN_PMIN))/n_L/baseMVA,
                ];
        end
    end
end
%%
% ���鿪������ Cjk
cost_up = sdpvar(n_gen, n_T);
C = [C, cost_up >= 0];
for k = 1: n_T
    for t = 1: k-1
         C = [C,
            cost_up(:,k) >= start_cost(:,t).*(u_state(gen(:,GEN_BUS),k) - sum(u_state(gen(:,GEN_BUS),[k-t: k-1]),2))
            ];       
    end
end
for i = 1: n_gen
    if (init_state(gen(i,GEN_BUS)) == 0)
        C = [C,
            cost_up(i,1) >= start_cost(i,init_down(i))*(u_state(gen(i,GEN_BUS),1)-init_down(i)*init_state(gen(i,GEN_BUS)))
            ];
    end
end
for k = 2: n_T
    for i = 1: n_gen
        if (init_state(gen(i,GEN_BUS)) == 0)
        C = [C,
            cost_up(i,k) >= start_cost(i,k+init_down(i)-1)*(u_state(gen(i,GEN_BUS),k)-sum(u_state(gen(i,GEN_BUS),[1: k-1]))-init_down(i)*init_state(gen(i,GEN_BUS)))
            ];
        end
    end
end
%% 
% �������Լ��
%ϵͳ����ƽ��Լ��
for t = 1: n_T
    C = [C,
        sum(gen_P(gen(:,GEN_BUS),t)) >= sum(PD(:,t)),
        ];
end
%%
% �������Լ��
% ��������
for t = 1: n_T
    if (t > 1)
    C = [C,
        %���Լ������2006������
        %A Computationally Efficient Mixed-Integer Linear Formulation for the Thermal Unit Commitment Problem
        %д�ģ���֪��Pmax*(1-u)������ʲô��
        %�������ƺ��������� (ramp-up & startup)    (18)
        gen_P_upper(gen(:,GEN_BUS),t) <= gen_P(gen(:,GEN_BUS),t-1) + RU.*u_state(gen(:,GEN_BUS),t-1) + ...
                                         SU.*(u_state(gen(:,GEN_BUS),t)-u_state(gen(:,GEN_BUS),t-1)) + ...
                                         (gen(:, GEN_PMAX)/baseMVA).*(1-u_state(gen(:,GEN_BUS),t)),
        %�������� (ramp-down)       (20)
        gen_P(gen(:,GEN_BUS),t-1) - gen_P(gen(:,GEN_BUS),t) <= RD.*u_state(gen(:,GEN_BUS),t) + ...
                                                               SD.*(u_state(gen(:,GEN_BUS),t-1)-u_state(gen(:,GEN_BUS),t)) + ...
                                                               (gen(:, GEN_PMAX)/baseMVA).*(1-u_state(gen(:,GEN_BUS),t-1)),
        ];
    end
    if (t < n_T)
        C = [C,
            %�ػ����� (shutdown)    (19)
            gen_P_upper(gen(:,GEN_BUS),t) <= (gen(:, GEN_PMAX)/baseMVA).*u_state(gen(:,GEN_BUS),t+1) + ...
                                             SD.*(u_state(gen(:,GEN_BUS),t)-u_state(gen(:,GEN_BUS),t+1)),
                                             ];
    end
end
%%
% �������Լ��
%��С����ʱ������
for i = 1: n_gen
    Gi = min(n_T, (min_up(i)-init_up(i))*init_state(gen(i,GEN_BUS)));
    %������ ��ʼ���м䣬��β
    %��ʼʱ���ǳ�ʼ״̬��Ӱ�죬�м䲻�迼��̫�࣬��β��֤�����Ժ�û�ع�
    if (Gi >= 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS), [1: Gi])) == Gi,
            ];
    end
    for t = Gi+1: n_T-min_up(i)+1
        if (t > 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS),[t: t+min_up(i)-1])) >= min_up(i).*(u_state(gen(i,GEN_BUS),t)-u_state(gen(i,GEN_BUS),t-1)),
            ];
        elseif (t == 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS),[t: t+min_up(i)-1])) >= min_up(i).*(u_state(gen(i,GEN_BUS),t)-init_state(gen(i,GEN_BUS))),
            ];        
        else
        end
    end
    for t = n_T-min_up(i)+2: n_T
        if (t > 1)
            C = [C,
                sum(u_state(gen(i,GEN_BUS),[t: n_T])) >= (n_T-t+1).*(u_state(gen(i,GEN_BUS),t)-u_state(gen(i,GEN_BUS),t-1)),
                ];
        elseif (t == 1)
            C = [C,
                sum(u_state(gen(i,GEN_BUS),[t: n_T])) >= (n_T-t+1).*(u_state(gen(i,GEN_BUS),t)-init_state(gen(i,GEN_BUS))),
                ];            
        else
        end
    end
end
%%
% �������Լ��
%��С�ػ�ʱ������ ͬ��С����ʱ������
for i = 1: n_gen
    Li = min(n_T, (min_down(i)-init_down(i))*(1-init_state(gen(i,GEN_BUS))));
    if (Li >= 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS), [1: Li])) == 0,
            ];
    end
    for t = Li+1: n_T-min_down(i)+1
        if (t > 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS), [t: t+min_down(i)-1])) <= min_down(i).*(1-u_state(gen(i,GEN_BUS),t-1)+u_state(gen(i,GEN_BUS),t)),
            ];
        elseif (t == 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS), [t: t+min_down(i)-1])) <= min_down(i).*(1-init_state(gen(i,GEN_BUS))+u_state(gen(i,GEN_BUS),t)),
            ];
        else
        end
    end
    for t = n_T-min_down(i)+2: n_T
        if (t > 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS),[t: n_T])) <= (n_T-t+1).*(1-u_state(gen(i,GEN_BUS),t-1)+u_state(gen(i,GEN_BUS),t)),
            ];
        elseif (t == 1)
        C = [C,
            sum(u_state(gen(i,GEN_BUS),[t: n_T])) <= (n_T-t+1).*(1-init_state(gen(i,GEN_BUS))+u_state(gen(i,GEN_BUS),t)),
            ];
        else
        end            
    end
end

%%
New_Br_temp = 1: n_bus;
New_Br_temp(gen(:, GEN_BUS)) = [];
C = [C,
    gen_P(New_Br_temp, :) == 0,
%     gen_Q(New_Br_temp, :) == 0,
    u_state(New_Br_temp, :) == 0      %���ǻ������ �Ƿ�����ڵ�ȡ0
    ];  %�Ƿ�����ڵ��й��޹�Ϊ0

%%
%��������
% ֧·����Լ��
for t = 1: n_T
    C = [C,
        PF_D(:, t) == Bf*Va(:, t) + Pfinj,
        ];
end

%%
%�ڵ㹦��ƽ��Լ��
for t = 1: n_T
    for i = 1: n_bus
        C = [C,
            gen_P(i,t) == PD(i,t) + ...
                          sum(PF_D(branch(:, F_BUS) == i,t)) - ...
                          sum(PF_D(branch(:, T_BUS) == i,t)) + ...
                          bus(i, BUS_GS)/baseMVA,
            ];
    end
end
%%
% ��ת����Լ��
for t = 1: n_T
    C = [C,
        sum(gen_P_upper(gen(:, GEN_BUS), t)) >= sum(spnningReserve(:, t))
        ];
end
%%
%������й�����Լ��
for  t = 1: n_T
    for i = 1: n_gen
        C = [C,
            gen_P_upper(gen(i, GEN_BUS),t) >= gen_P(gen(i, GEN_BUS),t) >= u_state(gen(i, GEN_BUS),t).*gen(i, GEN_PMIN)/baseMVA,
            u_state(gen(i, GEN_BUS),t).*gen(i, GEN_PMAX)/baseMVA >= gen_P_upper(gen(i, GEN_BUS),t) >= 0
            ];
    end
end

%%
%֧·����Լ��
% ���Խ�� �������ڹ���Լ��  P^2+Q^2<=S^2
% for i = 1: n_branch
%     if (branch(i, RATE_A) ~= 0)     %rateAΪ0����Ϊ����Ҫ��Ӱ�ȫԼ��
%         C = [C,
%             PF_D(i)^2+QF_D(i)^2 <= (branch(i, RATE_A)/baseMVA)^2
%             ];
%     end 
% end
% -Pmax <=P <= Pmax
for i = 1: n_branch
    if (branch(i, RATE_A) ~= 0)     %rateAΪ0����Ϊ����Ҫ��Ӱ�ȫԼ��
        C = [C,
            -k_safe*branch(i, RATE_A)/baseMVA <= PF_D(i,:) <= k_safe*branch(i, RATE_A)/baseMVA
            ];
    end
end
%%
% ����̬Լ��
%%
%������ɱ�������������2�κ���  ������Ҫ��д
opf_value = sum(gencost(:, GENCOST_C2)'*(gen_P(gen(:, GEN_BUS),:)*baseMVA).^2) + ...
            sum(gencost(:, GENCOST_C1)'* gen_P(gen(:, GEN_BUS),:)*baseMVA) + ...
            sum(gencost(:, GENCOST_C0)'*u_state(gen(:, GEN_BUS),:)) + ...
            sum(sum(cost_up));
%�ֶ����Ի���ʽ
opf_value = 0;
for i = 1: n_gen
    for t = 1: n_T
        opf_value = opf_value + A_gen(i)*u_state(gen(i,GEN_BUS),t);
        for l = 1: n_L
             opf_value = opf_value + Fij(i,l)*P_nl(i,l,t)*baseMVA;
        end
    end
end
opf_value = opf_value + sum(sum(cost_up));
%             ones(1,n_gen)*cost_up*ones(n_T,1);     %��Сֵ
        
%%     
%���� ����̫��
% ops = sdpsettings('solver','mosek','verbose',2,'usex0',0);       %ʹ�ó�ֵ ��Ҫ�ǵ�ѹȡ1
ops = sdpsettings('solver','cplex','verbose',2,'usex0',0);      
% ops.gurobi.MIPGap = 1e-2;
% ops.mosek.MSK_IPAR_MIO_CONIC_OUTER_APPROXIMATION = 'MSK_ON';
% ops.moesk.MSK_DPAR_OPTIMIZER_MAX_TIME = 300;
% ops.mosek.MSK_IPAR_MIO_HEURISTIC_LEVEL = 4;
% ops.mosek.MSK_DPAR_MIO_TOL_REL_GAP = 1e-6;
% ops.mosek.MSK_DPAR_MIO_REL_GAP_CONST = 1e-4;
%mosek ����Ҫyalmipת������׶Լ����cplex��gurobi��Ҫ �ܺ��ڴ�
% ops = sdpsettings('verbose',2);
% ops.sedumi.eps = 1e-6;
% ops.gurobi.MIPGap = 1e-6;
%%
toc
%���         
result = optimize(C, opf_value, ops);
toc(alltime)
%������
% gen_P = value(gen_P);
% gen_Q = value(gen_Q);
% xij_1 = value(xij_1);
% xij_2 = value(xij_2);
% x_i = value(x_i);
% PF_D = value(PF_D);
% QF_D = value(QF_D);
% PF_R = value(PF_R);
% QF_R = value(QF_R);
% u_state = value(u_state);

if result.problem == 0 % problem =0 �������ɹ� 
else
    error('������');
end  
plot([0: n_T], [init_gen_P(gen(:,GEN_BUS)) value(gen_P(gen(:,GEN_BUS),:))]);    %���������

gen_P = value(gen_P);
% gen_Q = value(gen_Q);
PF_D = value(PF_D);
u_state = value(u_state);
cost_up = value(cost_up);


%%


