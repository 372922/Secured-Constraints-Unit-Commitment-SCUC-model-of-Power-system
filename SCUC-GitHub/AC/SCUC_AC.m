%SCUC�������������̣����ǲ����˶���׶�ɳ�
clc;
clear;
close all;
clear all class;
warning off;

addpath('../example');
addpath('../function');

alltime = tic;
tic
%%
% ����
% casename = input('Please enter case name : ', 's');
casename = 'case14mod_SCUC';
% casename = 'case30mod';
k_safe = 0.95;          %��ȫϵ����������һ����ԣ�ȣ���Գ�����ȫԼ��

% ʱ����t ���ڻ�������Ż�
n_T = 24;

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
% gbus = gen(:, GEN_BUS);             % form generator vector

%%
%���ɾ������
[Ybus, Yf, Yt] = makeYbus(baseMVA, bus, branch);   % build admitance matrix
% G = real(Ybus);
% B = imag(Ybus);
% % G B �����ж��ǵ���ֵ�ĸ��� 
% g = -G;
% b = -B;

%%
% �������߱���
% ��������� �Ƿ�����ڵ�ȡ0
gen_P = sdpvar(n_bus, n_T);
gen_Q = sdpvar(n_bus, n_T);
gen_P_upper = sdpvar(n_bus, n_T);   %������й������Ͻ�
% ���ڵ��ѹ��ֵ ���
% Vm = sdpvar(n_bus, 1);      %��ֵ
% Va = sdpvar(n_bus, 1);      %���
% �ɳڱ��� ����
x_i = sdpvar(n_bus, n_T);                         %xi = Vi^2
% xij_1 = sdpvar(n_bus, n_bus, n_T, 'skew');           %xij1 = Vi*Vj*sin(Oi-Oj)  ���Գƾ��� A = -A'
% xij_2 = sdpvar(n_bus, n_bus, n_T, 'symmetric');      %xij2 = Vi*Vj*cos(Oi-Oj)  �Գƾ���   A = A'
xij_1 = sdpvar(n_branch, n_T);                    %xij_1 = Vi*Vj*sin(Oi-Oj)
xij_2 = sdpvar(n_branch, n_T);                    %xij_2 = Vi*Vj*cos(Oi-Oj)

% ��֧·����
PF_D = sdpvar(n_branch, n_T);     %P Flow Direct �����й����� 1->2
QF_D = sdpvar(n_branch, n_T);     %Q Flow Direct �����޹����� 1->2
PF_R = sdpvar(n_branch, n_T);     %P Flow Reverse �����й����� 2->1
QF_R = sdpvar(n_branch, n_T);     %Q Flow Reverse �����޹����� 2->1

% ����״̬
u_state = binvar(n_bus, n_T);     %��ĸ�������Ƿ�����ڵ�ȡ0
C = [];     %Լ��
% C = sdpvar(C)>=0;

assign(xij_1, 0);
assign(xij_2, 1);
assign(x_i, 1);

%% 
% �������Լ��
%ϵͳ����ƽ��Լ��
for t = 1: n_T
    C = [C,
        sum(gen_P(gen(:,GEN_BUS),t)) >= sum(PD(:,t)),
        ];
end
%%
% ��ת����Լ��
for t = 1: n_T
    C = [C,
        sum(gen_P_upper(gen(:, GEN_BUS), t)) >= sum(spnningReserve(:, t))
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
    gen_Q(New_Br_temp, :) == 0,
    gen_P_upper(New_Br_temp, :) == 0,
    u_state(New_Br_temp, :) == 0      %���ǻ������ �Ƿ�����ڵ�ȡ0
    ];  %�Ƿ�����ڵ��й��޹�Ϊ0
%%
% ����������ɳڱ���x��Լ�� 
for i = 1: n_branch
    m = branch(i, F_BUS);
    n = branch(i, T_BUS);
    for t = 1: n_T
    C = [C,
%         (2*xij_1(i,t)).^2 + (2*xij_2(i,t)).^2 + (x_i(m,t)-x_i(n,t)).^2 <= (x_i(m,t)+x_i(n,t)).^2
        rcone([xij_1(i,t); xij_2(i,t)], 0.5*x_i(m,t), x_i(n,t)),          
        ];
    end
end
%%
%��������
% ֧·����Լ��
for i = 1: n_branch
    f_bus = branch_f_bus(i);            % ֧·i����ʼĸ��  
    t_bus = branch_t_bus(i);            % ֧·i���ն�ĸ��
    
    gff = real(Yf(i,branch_f_bus(i)));
    gft = real(Yf(i,branch_t_bus(i)));
    bff = imag(Yf(i,branch_f_bus(i)));
    bft = imag(Yf(i,branch_t_bus(i)));
    
    gtf = real(Yt(i,branch_f_bus(i)));
    gtt = real(Yt(i,branch_t_bus(i)));
    btf = imag(Yt(i,branch_f_bus(i)));
    btt = imag(Yt(i,branch_t_bus(i)));
    C = [C,
        PF_D(i,:) == x_i(f_bus,:)*gff+xij_2(i,:)*gft+xij_1(i,:)*bft,
        QF_D(i,:) == -x_i(f_bus,:)*bff+xij_1(i,:)*gft-xij_2(i,:)*bft,

        PF_R(i,:) == x_i(t_bus,:)*gtt+xij_2(i,:)*gtf-xij_1(i,:)*btf,
        QF_R(i,:) == -x_i(t_bus,:)*btt-xij_1(i,:)*gtf-xij_2(i,:)*btf
        ];  %����·��������
end

%%
%�ڵ㹦��ƽ��Լ��
for i = 1: n_bus
    for t = 1: n_T
    C = [C,
        %ת���� n_T = 24 ��sum��ôдӦ���ǰ��м��������ϳ�һ��
        gen_P(i,t) == PD(i,t) + ...
                    sum(PF_D(branch(:, F_BUS) == i,t)) + ...
                    sum(PF_R(branch(:, T_BUS) == i,t)) + ...
                    x_i(i,t)*bus(i, BUS_GS)/baseMVA,
        gen_Q(i,t) == QD(i,t) + ...
                    sum(QF_D(branch(:, F_BUS) == i,t)) + ...
                    sum(QF_R(branch(:, T_BUS) == i,t)) - ...
                    x_i(i,t)*bus(i, BUS_BS)/baseMVA             %����Gs BsӰ��
        ];      %�ڵ㹦��ƽ�ⷽ��     %x_i = Vi^2
    end
end

%%
%���ڵ��ѹ��ֵԼ��
for t = 1: n_T
    C = [C,
        bus(:, BUS_Vmax).^2 >= x_i(bus(:, BUS_I), t) >= bus(:, BUS_Vmin).^2
        ];          %x_i = Vi^2
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
%������޹�����Լ��
for t = 1: n_T
    for i = 1: n_gen
        C = [C,
            %���ǻ������
            u_state(gen(i, GEN_BUS),t).*gen(i, GEN_QMAX)/baseMVA >= gen_Q(gen(i, GEN_BUS),t) >= u_state(gen(i, GEN_BUS),t).*gen(i, GEN_QMIN)/baseMVA
            ];
    end
end

%%
%֧·����Լ��
% -Pmax <=P <= Pmax
for i = 1: n_branch
    if (branch(i, RATE_A) ~= 0)     %rateAΪ0����Ϊ����Ҫ��Ӱ�ȫԼ��
        C = [C,
            -k_safe*branch(i, RATE_A)/baseMVA <= PF_D(i,:) <= k_safe*branch(i, RATE_A)/baseMVA
            ];
    end
end

%%
%����̬Լ��

%%
%������ɱ�������������2�κ���  ������Ҫ��д
obj_value = sum(gencost(:, GENCOST_C2)'*(gen_P(gen(:, GEN_BUS),:)*baseMVA).^2) + ...
            sum(gencost(:, GENCOST_C1)'* gen_P(gen(:, GEN_BUS),:)*baseMVA) + ...
            sum(gencost(:, GENCOST_C0)'*u_state(gen(:, GEN_BUS),:));
        
%%     
ops = sdpsettings('solver','cplex','verbose',2,'usex0',1);       %ʹ�ó�ֵ ��Ҫ�ǵ�ѹȡ1
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
result = optimize(C, obj_value, ops);
toc(alltime)
if result.problem == 0 % problem =0 �������ɹ�
%     value(x)
%     value(opf_value)   
else
%     tic
%     ops = sdpsettings('solver','cplex','verbose',2,'usex0',1);       %ʹ�ó�ֵ ��Ҫ�ǵ�ѹȡ1
%     result = optimize(C, opf_value, ops);
%     toc
    error('������');
end  
plot([0: n_T], [init_gen_P(gen(:,GEN_BUS)) value(gen_P(gen(:,GEN_BUS),:))]);    %���������

gen_P = value(gen_P(gen(:,GEN_BUS),:));
gen_Q = value(gen_Q(gen(:,GEN_BUS),:));
xij_1 = value(xij_1);
xij_2 = value(xij_2);
x_i = value(x_i);
PF_D = value(PF_D);
% QF_D = value(QF_D);
PF_R = value(PF_R);
% QF_R = value(QF_R);
u_state = value(u_state(gen(:,GEN_BUS),:));

