import random
import datetime
import uuid

# ==================== 配置参数 ====================
ROW_COUNT_PER_TABLE = 1000        # 每张表生成记录数（可调整）
START_DATE = datetime.date(2023, 1, 1)
END_DATE = datetime.date(2024, 12, 31)
import os
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "output", "insert_data_full.sql")

# 固定分区日期（所有表使用同一批分区值，可按需调整）
PARTITION_DT = "2024-12-31"

# 随机种子（保证可复现）
random.seed(42)

# ==================== 辅助函数 ====================
def random_date(start, end):
    """生成随机日期"""
    return start + datetime.timedelta(days=random.randint(0, (end - start).days))

def random_phone():
    return f"1{random.choice(['3','5','7','8','9'])}{random.randint(100000000,999999999)}"

def random_id_no(prefix="110101"):
    return prefix + str(random.randint(19000101, 20231231)) + str(random.randint(1000,9999))

def random_vin():
    return ''.join(random.choices('0123456789ABCDEFGHJKLMNPRSTUVWXYZ', k=17))

def random_plate():
    letters = random.choices('ABCDEFGHJKLMNPQRSTUVWXYZ', k=2)
    numbers = random.choices('0123456789', k=5)
    return '京' + ''.join(letters) + ''.join(numbers)

def random_company_name():
    prefixes = ['平安', '太平洋', '人保', '大地', '阳光', '中华', '天安', '华泰', '永安', '安邦']
    suffixes = ['保险', '科技', '贸易', '物流', '咨询', '服务', '制造', '建筑', '餐饮', '文化']
    return random.choice(prefixes) + random.choice(suffixes) + random.choice(['有限公司', '集团', '公司'])

def random_address():
    cities = ['北京市', '上海市', '广州市', '深圳市', '杭州市', '成都市', '武汉市', '西安市']
    streets = ['中山路', '解放路', '人民路', '建设路', '和平路', '新华路', '朝阳路', '青年路']
    return random.choice(cities) + random.choice(streets) + str(random.randint(1, 999)) + '号'

def generate_id(prefix, length=8):
    """生成带前缀的唯一ID，例如 C0000001"""
    num = random.randint(1, 10**length)
    return f"{prefix}{num:0{length}d}"

# ==================== 数据存储容器 ====================
# 用于跨表引用的ID列表
customer_ids = []          # 个人+企业混合
individual_ids = []
enterprise_ids = []
vehicle_ids = []
property_ids = []
product_ids = []
coverage_ids = []
channel_ids = []
agent_ids = []
policy_ids = []
claim_ids = []
report_ids = []

# 生成客户ID函数（个人/企业共用）
def get_customer_id():
    return random.choice(customer_ids)

# ==================== 生成维度表数据 ====================
def generate_dim_customer_individual(n):
    data = []
    for i in range(n):
        cust_id = generate_id('C', 9)
        individual_ids.append(cust_id)
        customer_ids.append(cust_id)
        row = {
            'customer_id': cust_id,
            'name': random.choice(['张','王','李','刘','陈','赵','周','吴'])+random.choice(['伟','强','芳','娜','涛','军','勇','静']),
            'gender': random.choice(['男','女']),
            'birthday': random_date(datetime.date(1950,1,1), datetime.date(2000,12,31)).strftime('%Y-%m-%d'),
            'id_type': '身份证',
            'id_no': random_id_no(),
            'occupation': random.choice(['工程师','教师','医生','律师','会计','销售','司机','工人','农民','自由职业']),
            'income_level': random.choice(['低','中低','中产','中高','高']),
            'education': random.choice(['初中','高中','大专','本科','硕士','博士']),
            'marital_status': random.choice(['未婚','已婚','离异','丧偶']),
            'has_children': random.choice(['true','false']),
            'driving_license_no': random_id_no('11'),
            'first_license_date': random_date(datetime.date(2000,1,1), datetime.date(2020,12,31)).strftime('%Y-%m-%d'),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_enterprise(n):
    data = []
    for i in range(n):
        cust_id = generate_id('E', 9)
        enterprise_ids.append(cust_id)
        customer_ids.append(cust_id)
        row = {
            'customer_id': cust_id,
            'company_name': random_company_name(),
            'credit_code': ''.join(random.choices('0123456789ABCDEFGHJKLMNPQRSTUVWXYZ', k=18)),
            'legal_rep': random.choice(['张','王','李','刘','陈'])+random.choice(['伟','强','军']),
            'registered_capital': round(random.uniform(100000, 100000000), 2),
            'industry_code': random.choice(['I6510','I6520','F5110','G5310','H6110']),
            'established_date': random_date(datetime.date(1990,1,1), datetime.date(2020,12,31)).strftime('%Y-%m-%d'),
            'employee_count': random.randint(10, 5000),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_contact(n):
    data = []
    for i in range(n):
        row = {
            'contact_id': generate_id('CT', 9),
            'customer_id': random.choice(enterprise_ids),
            'name': random.choice(['张','王','李'])+random.choice(['经理','主管','助理']),
            'position': random.choice(['法定代表人','财务总监','人事经理','采购经理','销售经理']),
            'phone': random_phone(),
            'email': f"contact{i}@example.com",
            'is_primary': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_relation(n):
    data = []
    for i in range(n):
        row = {
            'relation_id': generate_id('R', 9),
            'from_customer_id': random.choice(customer_ids),
            'to_customer_id': random.choice(customer_ids),
            'relation_type': random.choice(['夫妻','母子','父子','控股','关联']),
            'start_date': random_date(datetime.date(2000,1,1), datetime.date(2020,12,31)).strftime('%Y-%m-%d'),
            'end_date': random.choice(['NULL', random_date(datetime.date(2021,1,1), datetime.date(2024,12,31)).strftime('%Y-%m-%d')]),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_address(n):
    data = []
    for i in range(n):
        row = {
            'address_id': generate_id('A', 9),
            'customer_id': random.choice(customer_ids),
            'address_type': random.choice(['家庭','公司','通讯']),
            'province': random.choice(['北京市','上海市','广东省','浙江省','江苏省']),
            'city': random.choice(['市辖区','广州市','杭州市','南京市','深圳市']),
            'district': random.choice(['朝阳区','海淀区','浦东新区','天河区','西湖区']),
            'detail_address': f"{random.randint(1,999)}号院{random.randint(1,10)}号楼",
            'postcode': str(random.randint(100000, 999999)),
            'is_default': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_vehicle(n):
    data = []
    for i in range(n):
        vid = generate_id('V', 9)
        vehicle_ids.append(vid)
        row = {
            'vehicle_id': vid,
            'customer_id': random.choice(individual_ids + enterprise_ids),
            'plate_no': random_plate(),
            'vin': random_vin(),
            'brand': random.choice(['大众','丰田','本田','日产','别克','宝马','奔驰','奥迪','比亚迪','特斯拉']),
            'model': random.choice(['轿车','SUV','MPV','跑车','皮卡']),
            'purchase_price': round(random.uniform(50000, 500000), 2),
            'purchase_date': random_date(datetime.date(2010,1,1), datetime.date(2023,12,31)).strftime('%Y-%m-%d'),
            'seat_count': random.choice([2,4,5,7,9]),
            'displacement': round(random.uniform(1.0, 4.0), 2),
            'usage_type': random.choice(['家庭自用','营运','非营业']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_customer_property(n):
    data = []
    for i in range(n):
        pid = generate_id('P', 9)
        property_ids.append(pid)
        row = {
            'property_id': pid,
            'customer_id': random.choice(individual_ids + enterprise_ids),
            'property_type': random.choice(['房屋','厂房','设备','仓库']),
            'address': random_address(),
            'area': round(random.uniform(50, 10000), 2),
            'structure': random.choice(['砖混','钢混','钢结构','木结构']),
            'build_year': random.randint(1980, 2023),
            'insured_value': round(random.uniform(100000, 10000000), 2),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_customer_score(n):
    data = []
    for i in range(n):
        row = {
            'score_id': generate_id('S', 9),
            'customer_id': random.choice(customer_ids),
            'score_date': random_date(datetime.date(2023,1,1), datetime.date(2024,12,31)).strftime('%Y-%m-%d'),
            'risk_score': round(random.uniform(0,1), 4),
            'value_score': round(random.uniform(0,1), 4),
            'loyalty_score': round(random.uniform(0,1), 4),
            'comprehensive_score': round(random.uniform(0,1), 4),
            'model_version': f"v{random.randint(1,3)}.{random.randint(0,9)}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_product_line(n):
    lines = [
        ('L001','车险','CAR','机动车保险','0101'),
        ('L002','意外险','ACC','意外伤害保险','0201'),
        ('L003','健康险','HEA','健康保险','0301'),
        ('L004','责任险','LIA','责任保险','0401'),
        ('L005','企财险','PRO','企业财产保险','0501'),
    ]
    # 如果n>5，则重复或随机组合
    data = []
    for i in range(min(n, len(lines))):
        row = {
            'line_id': lines[i][0],
            'line_name': lines[i][1],
            'line_code': lines[i][2],
            'risk_category': lines[i][3],
            'regulator_code': lines[i][4],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_product(n):
    products = [
        ('P001','L001','机动车商业保险','CAR001','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P002','L001','交强险','CAR002','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P003','L002','个人意外伤害险','ACC001','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P004','L002','团体意外险','ACC002','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P005','L003','百万医疗险','HEA001','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P006','L004','公众责任险','LIA001','在售','2023-01-01','2024-12-31','true','NULL'),
        ('P007','L005','企业财产险','PRO001','在售','2023-01-01','2024-12-31','true','NULL'),
    ]
    data = []
    for i in range(min(n, len(products))):
        product_ids.append(products[i][0])
        row = {
            'product_id': products[i][0],
            'line_id': products[i][1],
            'product_name': products[i][2],
            'product_code': products[i][3],
            'status': products[i][4],
            'effective_date': products[i][5],
            'expiry_date': products[i][6],
            'is_main_product': products[i][7],
            'parent_product_id': products[i][8],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_coverage(n):
    coverages = [
        ('COV001','P001','CAR_DAMAGE','车损险','车辆损失保障','true'),
        ('COV002','P001','THIRD_PARTY','三者险','第三方责任保障','true'),
        ('COV003','P001','THEFT','盗抢险','全车盗抢保障','false'),
        ('COV004','P002','COMPULSORY','交强险','强制保险','true'),
        ('COV005','P003','ACC_DEATH','意外身故','意外身故保障','true'),
        ('COV006','P004','ACC_MEDICAL','意外医疗','意外医疗保障','true'),
        ('COV007','P005','HOSPITAL','住院医疗','住院费用补偿','true'),
    ]
    data = []
    for i in range(min(n, len(coverages))):
        coverage_ids.append(coverages[i][0])
        row = {
            'coverage_id': coverages[i][0],
            'product_id': coverages[i][1],
            'coverage_code': coverages[i][2],
            'coverage_name': coverages[i][3],
            'coverage_desc': coverages[i][4],
            'is_required': coverages[i][5],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_rate_factor(n):
    factors = [
        ('F001','P001','年龄系数','系数','18-25:1.2,26-35:1.0','1.0'),
        ('F002','P001','车型系数','系数','轿车:1.0,SUV:1.1','1.0'),
        ('F003','P002','NCD系数','系数','连续3年无赔:0.6','1.0'),
    ]
    data = []
    for i in range(min(n, len(factors))):
        row = {
            'factor_id': factors[i][0],
            'product_id': factors[i][1],
            'factor_name': factors[i][2],
            'factor_type': factors[i][3],
            'value_range': factors[i][4],
            'weight': float(factors[i][5]),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_rate_table(n):
    data = []
    for i in range(n):
        row = {
            'rate_id': generate_id('R', 9),
            'product_id': random.choice(product_ids),
            'coverage_id': random.choice(coverage_ids),
            'effective_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'expiry_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'rate_type': random.choice(['固定','阶梯']),
            'rate_value': round(random.uniform(0.0001, 0.1), 6),
            'min_premium': round(random.uniform(100, 1000), 2),
            'max_premium': round(random.uniform(1000, 10000), 2),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_clause(n):
    clauses = [
        ('CLA001','P001','EXCL001','免责条款','战争、核爆炸等','免责'),
        ('CLA002','P001','DUTY001','被保险人义务','及时报案','基本'),
        ('CLA003','P002','SPEC001','特约条款','指定驾驶员','特约'),
    ]
    data = []
    for i in range(min(n, len(clauses))):
        row = {
            'clause_id': clauses[i][0],
            'product_id': clauses[i][1],
            'clause_code': clauses[i][2],
            'clause_title': clauses[i][3],
            'clause_content': clauses[i][4],
            'clause_type': clauses[i][5],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_channel(n):
    channels = [
        ('CH001','XX车商','车商',None,1,'月结'),
        ('CH002','XX代理公司','代理',None,1,'月结'),
        ('CH003','官网','网销',None,1,'实时'),
        ('CH004','电销中心','直销',None,1,'月结'),
    ]
    data = []
    for i in range(min(n, len(channels))):
        channel_ids.append(channels[i][0])
        row = {
            'channel_id': channels[i][0],
            'channel_name': channels[i][1],
            'channel_type': channels[i][2],
            'parent_channel_id': channels[i][3],
            'channel_level': channels[i][4],
            'settle_type': channels[i][5],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_agent(n):
    data = []
    for i in range(n):
        aid = generate_id('AG', 9)
        agent_ids.append(aid)
        row = {
            'agent_id': aid,
            'agent_name': random.choice(['张','王','李','刘'])+random.choice(['伟','强','芳']),
            'id_no': random_id_no(),
            'license_no': f"LIC{random.randint(10000,99999)}",
            'entry_date': random_date(datetime.date(2010,1,1), datetime.date(2023,12,31)).strftime('%Y-%m-%d'),
            'channel_id': random.choice(channel_ids),
            'team_id': f"TM{random.randint(1,10):03d}",
            'manager_id': random.choice([None, 'AG001']) if random.random()>0.3 else None,
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_agency(n):
    data = []
    for i in range(n):
        row = {
            'agency_id': generate_id('A', 9),
            'agency_name': random_company_name() + '代理',
            'credit_code': ''.join(random.choices('0123456789ABCDEFGHJKLMNPQRSTUVWXYZ', k=18)),
            'channel_id': random.choice(channel_ids),
            'cooperation_start_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'cooperation_end_date': random.choice([None, random_date(START_DATE, END_DATE).strftime('%Y-%m-%d')]),
            'settle_cycle': random.choice(['月结','季结','年结']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_commission_rule(n):
    data = []
    for i in range(n):
        row = {
            'rule_id': generate_id('CR', 9),
            'channel_id': random.choice(channel_ids),
            'product_id': random.choice(product_ids),
            'effective_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'expiry_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'commission_rate': round(random.uniform(0.05, 0.25), 4),
            'commission_type': random.choice(['比例','固定']),
            'is_trial': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_application(n):
    data = []
    for i in range(n):
        app_id = generate_id('APP', 8)
        row = {
            'application_id': app_id,
            'customer_id': random.choice(customer_ids),
            'product_id': random.choice(product_ids),
            'channel_id': random.choice(channel_ids),
            'agent_id': random.choice(agent_ids + [None]),
            'application_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'start_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'end_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'status': random.choice(['待核保','已核保','拒保','撤单']),
            'underwrite_status': random.choice(['通过','拒绝','人工审核']),
            'underwrite_time': 'current_timestamp()',
            'underwriter_id': f"UW{random.randint(1,50):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_application_item(n):
    data = []
    for i in range(n):
        row = {
            'item_id': generate_id('I', 9),
            'application_id': random.choice([f"APP{random.randint(20230000,20249999)}" for _ in range(1)]),  # 需要关联已有投保单
            'coverage_id': random.choice(coverage_ids),
            'insured_amount': round(random.uniform(10000, 1000000), 2),
            'premium': round(random.uniform(100, 10000), 2),
            'rate_applied': round(random.uniform(0.001, 0.05), 6),
            'is_main_item': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_policy(n):
    data = []
    for i in range(n):
        pid = generate_id('POL', 10)
        policy_ids.append(pid)
        row = {
            'policy_id': pid,
            'application_id': random.choice([f"APP{random.randint(20230000,20249999)}" for _ in range(1)]),
            'policy_no': f"PD{random.randint(24000001,24999999)}",
            'customer_id': random.choice(customer_ids),
            'product_id': random.choice(product_ids),
            'channel_id': random.choice(channel_ids),
            'agent_id': random.choice(agent_ids + [None]),
            'issue_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'start_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'end_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'total_premium': round(random.uniform(500, 20000), 2),
            'total_amount': round(random.uniform(50000, 2000000), 2),
            'payment_method': random.choice(['年缴','月缴','季缴']),
            'payment_frequency': random.choice([1,12,4]),
            'status': random.choice(['有效','到期','退保','复效']),
            'is_renewal': random.choice(['true','false']),
            'previous_policy_id': random.choice([None, random.choice(policy_ids)]) if policy_ids else None,
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_policy_item(n):
    data = []
    for i in range(n):
        row = {
            'item_id': generate_id('PI', 9),
            'policy_id': random.choice(policy_ids),
            'coverage_id': random.choice(coverage_ids),
            'insured_amount': round(random.uniform(10000, 1000000), 2),
            'premium': round(random.uniform(100, 10000), 2),
            'deductible': round(random.uniform(0, 2000), 2),
            'rate_applied': round(random.uniform(0.001, 0.05), 6),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_policy_insured(n):
    data = []
    for i in range(n):
        row = {
            'insured_id': generate_id('IN', 9),
            'policy_id': random.choice(policy_ids),
            'insured_type': random.choice(['个人','企业']),
            'customer_id': random.choice(customer_ids),
            'insured_name': random.choice(['张三','李四','王五']),
            'id_no': random_id_no(),
            'relationship': random.choice(['本人','配偶','子女','父母','员工']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_policy_beneficiary(n):
    data = []
    for i in range(n):
        row = {
            'beneficiary_id': generate_id('BN', 9),
            'policy_id': random.choice(policy_ids),
            'beneficiary_type': random.choice(['个人','企业']),
            'customer_id': random.choice(customer_ids),
            'beneficiary_name': random.choice(['张','王','李'])+'某',
            'id_no': random_id_no(),
            'benefit_ratio': round(random.uniform(0,1), 4),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_policy_vehicle(n):
    data = []
    for i in range(min(n, len(policy_ids) * 2)):  # 确保车辆数不超过保单数太多
        row = {
            'policy_id': random.choice(policy_ids),
            'vehicle_id': random.choice(vehicle_ids),
            'usage_type': random.choice(['家庭自用','营运']),
            'mileage': random.randint(0, 100000),
            'is_new_car': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_policy_property(n):
    data = []
    for i in range(min(n, len(policy_ids) * 2)):
        row = {
            'policy_id': random.choice(policy_ids),
            'property_id': random.choice(property_ids),
            'location': random_address(),
            'occupation_status': random.choice(['自用','出租','闲置']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_endorsement(n):
    data = []
    for i in range(n):
        row = {
            'endorsement_id': generate_id('EN', 9),
            'policy_id': random.choice(policy_ids),
            'endorsement_type': random.choice(['加保','减保','退保','信息变更']),
            'application_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'effective_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'status': random.choice(['待批','已批','拒绝']),
            'previous_premium': round(random.uniform(500, 20000), 2),
            'new_premium': round(random.uniform(500, 20000), 2),
            'previous_amount': round(random.uniform(50000, 2000000), 2),
            'new_amount': round(random.uniform(50000, 2000000), 2),
            'reason_code': random.choice(['001','002','003']),
            'approver_id': f"AP{random.randint(1,20):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_endorsement_item(n):
    data = []
    for i in range(n):
        row = {
            'item_id': generate_id('EI', 9),
            'endorsement_id': random.choice([f"EN{random.randint(20230000,20249999)}" for _ in range(1)]),
            'coverage_id': random.choice(coverage_ids),
            'change_type': random.choice(['增加','减少','修改']),
            'previous_value': str(random.randint(0,1000)),
            'new_value': str(random.randint(0,1000)),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_coinsurance(n):
    data = []
    for i in range(min(n, len(policy_ids)//5)):  # 共保较少
        row = {
            'coinsurance_id': generate_id('CO', 9),
            'policy_id': random.choice(policy_ids),
            'role': random.choice(['主共','从共']),
            'company_name': random_company_name(),
            'share_ratio': round(random.uniform(0.1, 0.5), 4),
            'share_premium': round(random.uniform(1000, 50000), 2),
            'share_amount': round(random.uniform(100000, 5000000), 2),
            'leader_id': generate_id('L', 8),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_treaty_reinsurance(n):
    data = []
    for i in range(min(n, len(policy_ids)//10)):
        row = {
            'treaty_id': generate_id('T', 9),
            'policy_id': random.choice(policy_ids),
            'treaty_code': f"TREATY{random.randint(1,10)}",
            'ceding_company': '本公司',
            'reinsurance_type': random.choice(['比例','溢额']),
            'share_ratio': round(random.uniform(0.1, 0.5), 4),
            'premium_ceded': round(random.uniform(500, 10000), 2),
            'commission_rate': round(random.uniform(0.05, 0.15), 4),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_facultative_reinsurance(n):
    data = []
    for i in range(min(n, len(policy_ids)//10)):
        row = {
            'facultative_id': generate_id('F', 9),
            'policy_id': random.choice(policy_ids),
            'reinsurer_id': random.choice([f"RE{random.randint(1,5):02d}" for _ in range(1)]),
            'risk_unit': random.choice(['厂房A','设备B','仓库C']),
            'share_ratio': round(random.uniform(0.1, 0.5), 4),
            'premium_ceded': round(random.uniform(500, 10000), 2),
            'commission_rate': round(random.uniform(0.05, 0.15), 4),
            'approval_status': random.choice(['待批','已批','拒绝']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_risk_unit(n):
    data = []
    for i in range(min(n, len(policy_ids))):
        row = {
            'unit_id': generate_id('U', 9),
            'policy_id': random.choice(policy_ids),
            'unit_type': random.choice(['厂房','仓库','设备']),
            'description': f"单元{i}",
            'location': random_address(),
            'insured_value': round(random.uniform(100000, 10000000), 2),
            'risk_level': random.choice(['低','中','高']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_policy_status_history(n):
    data = []
    for i in range(n):
        row = {
            'history_id': generate_id('H', 9),
            'policy_id': random.choice(policy_ids),
            'status': random.choice(['待核保','已核保','有效','到期','退保']),
            'change_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'change_reason': random.choice(['新保','续保','批改','到期']),
            'operator_id': f"OP{random.randint(1,30):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_report(n):
    data = []
    for i in range(n):
        rid = generate_id('RPT', 9)
        report_ids.append(rid)
        row = {
            'report_id': rid,
            'policy_id': random.choice(policy_ids),
            'report_no': f"RP{random.randint(2400001,2499999)}",
            'report_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'reporter_name': random.choice(['张三','李四','王五']),
            'reporter_contact': random_phone(),
            'report_type': random.choice(['本人','他人']),
            'accident_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'accident_address': random_address(),
            'accident_desc': random.choice(['追尾','刮擦','碰撞','火灾','水淹']),
            'loss_type': random.choice(['车损','人伤','三者']),
            'report_status': random.choice(['待处理','已处理']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_accident(n):
    data = []
    for i in range(min(n, len(report_ids))):
        row = {
            'accident_id': generate_id('ACC', 9),
            'report_id': random.choice(report_ids),
            'accident_type': random.choice(['单方','双方','多方']),
            'accident_cause': random.choice(['碰撞','火灾','水淹','盗抢']),
            'accident_grade': random.choice(['轻微','一般','重大']),
            'weather': random.choice(['晴','雨','雪','雾']),
            'traffic_control': random.choice(['无','有']),
            'third_party_info': random.choice(['无','有第三方车辆']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_survey(n):
    data = []
    for i in range(min(n, len(report_ids))):
        row = {
            'survey_id': generate_id('SUR', 9),
            'report_id': random.choice(report_ids),
            'survey_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'surveyor_id': f"SU{random.randint(1,20):03d}",
            'survey_type': random.choice(['现场','远程']),
            'survey_address': random_address(),
            'site_condition': random.choice(['正常','异常']),
            'photos_count': random.randint(0,20),
            'is_original_site': random.choice(['true','false']),
            'survey_conclusion': random.choice(['事故属实','虚假报案','责任明确']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_loss_assessment(n):
    data = []
    for i in range(min(n, len(report_ids))):
        row = {
            'assessment_id': generate_id('LA', 9),
            'report_id': random.choice(report_ids),
            'assessment_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'assessor_id': f"AS{random.randint(1,20):03d}",
            'labor_cost': round(random.uniform(0, 5000), 2),
            'parts_cost': round(random.uniform(0, 20000), 2),
            'repair_fee': round(random.uniform(0, 1000), 2),
            'total_loss': round(random.uniform(1000, 50000), 2),
            'assessment_detail': random.choice(['更换保险杠','钣金喷漆']),
            'is_agreed': random.choice(['true','false']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_loss_item(n):
    data = []
    for i in range(n):
        row = {
            'item_id': generate_id('LI', 9),
            'assessment_id': random.choice([f"LA{random.randint(20230000,20249999)}" for _ in range(1)]),
            'part_name': random.choice(['前保险杠','大灯','车门','发动机']),
            'part_code': f"P{random.randint(1000,9999)}",
            'damage_type': random.choice(['破裂','变形','损坏']),
            'repair_method': random.choice(['更换','修复']),
            'unit_price': round(random.uniform(100, 5000), 2),
            'quantity': random.randint(1,5),
            'amount': round(random.uniform(100, 5000), 2),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_claim(n):
    data = []
    for i in range(min(n, len(report_ids))):
        cid = generate_id('CLM', 9)
        claim_ids.append(cid)
        row = {
            'claim_id': cid,
            'report_id': random.choice(report_ids),
            'claim_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'claim_handler': f"CH{random.randint(1,20):03d}",
            'claim_amount': round(random.uniform(1000, 50000), 2),
            'deductible_applied': random.choice(['true','false']),
            'deductible_amount': round(random.uniform(0, 2000), 2),
            'net_paid': round(random.uniform(1000, 50000), 2),
            'payment_target': random.choice(['被保险人','修理厂']),
            'payment_account': random.choice(['622202****1234','621700****5678']),
            'claim_status': random.choice(['已核','拒赔','待支付']),
            'reject_reason': random.choice(['不在保障范围','虚假报案','无']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_recovery(n):
    data = []
    for i in range(min(n, len(claim_ids)//10)):
        row = {
            'recovery_id': generate_id('REC', 9),
            'claim_id': random.choice(claim_ids),
            'recovery_type': random.choice(['代位','诉讼']),
            'recovery_target': random_company_name(),
            'recovery_amount': round(random.uniform(1000, 20000), 2),
            'recovery_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'recovery_status': random.choice(['进行中','已完成','失败']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_injury_case(n):
    data = []
    for i in range(min(n, len(report_ids)//5)):
        row = {
            'injury_id': generate_id('INJ', 9),
            'report_id': random.choice(report_ids),
            'injured_name': random.choice(['张','王','李'])+'某',
            'injured_id_no': random_id_no(),
            'injured_relation': random.choice(['本人','乘客','三者']),
            'injury_degree': random.choice(['轻','中','重','死亡']),
            'hospital_name': random.choice(['人民医院','中医院','骨科医院']),
            'medical_fee': round(random.uniform(1000, 100000), 2),
            'disability_grade': random.choice(['无','十级','九级','一级']),
            'nursing_fee': round(random.uniform(0, 20000), 2),
            'compensation_detail': '医药费、误工费',
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_third_party(n):
    data = []
    for i in range(min(n, len(report_ids)//5)):
        row = {
            'third_id': generate_id('TH', 9),
            'report_id': random.choice(report_ids),
            'third_type': random.choice(['车','人','物']),
            'third_name': random.choice(['张','王','李'])+'某',
            'third_id_no': random_id_no(),
            'third_vehicle': random_plate(),
            'third_insurance': random.choice(['有保险','无保险']),
            'third_liability_ratio': round(random.uniform(0,1), 4),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_reserve(n):
    data = []
    for i in range(min(n, len(report_ids))):
        row = {
            'reserve_id': generate_id('RS', 9),
            'report_id': random.choice(report_ids),
            'reserve_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'reserve_type': random.choice(['未决','已发生未报告']),
            'reserve_amount': round(random.uniform(1000, 50000), 2),
            'reserve_reason': random.choice(['预估','精算调整']),
            'actuary_id': f"AC{random.randint(1,10):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_fraud_alert(n):
    data = []
    for i in range(min(n, len(report_ids)//10)):
        row = {
            'alert_id': generate_id('FA', 9),
            'report_id': random.choice(report_ids),
            'alert_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'alert_rule': random.choice(['Rule001','Rule002','Rule003']),
            'alert_score': round(random.uniform(0,1), 4),
            'alert_level': random.choice(['高','中','低']),
            'handler_id': f"HD{random.randint(1,20):03d}",
            'handling_status': random.choice(['待处理','处理中','已处理']),
            'handling_result': random.choice(['确认欺诈','误报','待定']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_claim_status_history(n):
    data = []
    for i in range(min(n, len(claim_ids))):
        row = {
            'history_id': generate_id('CH', 9),
            'claim_id': random.choice(claim_ids),
            'status': random.choice(['已报案','查勘中','定损中','核赔中','已赔付','拒赔']),
            'change_time': f"'{random_date(START_DATE, END_DATE)} {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}'",
            'change_reason': random.choice(['报案','查勘完成','定损完成','核赔完成']),
            'operator_id': f"OP{random.randint(1,30):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_premium_payment(n):
    data = []
    for i in range(min(n, len(policy_ids))):
        row = {
            'payment_id': generate_id('PM', 9),
            'policy_id': random.choice(policy_ids),
            'payment_no': f"PY{random.randint(2400001,2499999)}",
            'payment_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'payment_amount': round(random.uniform(500, 20000), 2),
            'payment_method': random.choice(['微信','支付宝','银行卡','现金']),
            'payment_status': random.choice(['成功','失败']),
            'receipt_no': f"RC{random.randint(2400001,2499999)}",
            'bank_account': random.choice(['622202****1234','621700****5678']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_claim_payment(n):
    data = []
    for i in range(min(n, len(claim_ids))):
        row = {
            'payment_id': generate_id('CP', 9),
            'claim_id': random.choice(claim_ids),
            'payment_no': f"CY{random.randint(2400001,2499999)}",
            'payment_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'payment_amount': round(random.uniform(500, 50000), 2),
            'payment_target': random.choice(['被保险人','修理厂']),
            'payment_account': random.choice(['622202****1234','621700****5678']),
            'payment_status': random.choice(['成功','失败']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_commission_settlement(n):
    data = []
    for i in range(min(n, len(policy_ids))):
        row = {
            'settlement_id': generate_id('CS', 9),
            'policy_id': random.choice(policy_ids),
            'channel_id': random.choice(channel_ids),
            'agent_id': random.choice(agent_ids + [None]),
            'settlement_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'premium': round(random.uniform(500, 20000), 2),
            'commission_rate': round(random.uniform(0.05, 0.25), 4),
            'commission_amount': round(random.uniform(50, 5000), 2),
            'tax_amount': round(random.uniform(5, 500), 2),
            'net_amount': round(random.uniform(45, 4500), 2),
            'settlement_status': random.choice(['待结','已结','作废']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_account_receivable(n):
    data = []
    for i in range(min(n, len(policy_ids)//2)):
        row = {
            'receivable_id': generate_id('AR', 9),
            'policy_id': random.choice(policy_ids),
            'due_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'amount_due': round(random.uniform(500, 20000), 2),
            'amount_paid': round(random.uniform(0, 20000), 2),
            'balance': round(random.uniform(0, 10000), 2),
            'overdue_days': random.randint(0, 90),
            'collection_status': random.choice(['正常','逾期','已结清']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_account_payable(n):
    data = []
    for i in range(min(n, len(claim_ids)//2)):
        row = {
            'payable_id': generate_id('AP', 9),
            'claim_id': random.choice(claim_ids),
            'due_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'amount_due': round(random.uniform(500, 50000), 2),
            'amount_paid': round(random.uniform(0, 50000), 2),
            'balance': round(random.uniform(0, 20000), 2),
            'payment_status': random.choice(['待付','已付','逾期']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_premium_income(n):
    data = []
    for i in range(min(n, len(policy_ids))):
        row = {
            'income_id': generate_id('PI', 9),
            'policy_id': random.choice(policy_ids),
            'accounting_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'premium_earned': round(random.uniform(100, 10000), 2),
            'unearned_premium': round(random.uniform(100, 10000), 2),
            'deferred_acquisition_cost': round(random.uniform(10, 1000), 2),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_incurred_loss(n):
    data = []
    for i in range(min(n, len(claim_ids))):
        row = {
            'loss_id': generate_id('IL', 9),
            'claim_id': random.choice(claim_ids),
            'accounting_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'loss_incurred': round(random.uniform(1000, 50000), 2),
            'loss_adjustment_expense': round(random.uniform(100, 5000), 2),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_reserve_ledger(n):
    data = []
    for i in range(n):
        row = {
            'ledger_id': generate_id('RL', 9),
            'reserve_type': random.choice(['未决','已发生未报告','理赔费用']),
            'as_of_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'reserve_amount': round(random.uniform(100000, 10000000), 2),
            'change_amount': round(random.uniform(-100000, 100000), 2),
            'change_reason': random.choice(['新计提','冲回','调整']),
            'actuary_id': f"AC{random.randint(1,10):03d}",
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_dim_reinsurer(n):
    reinsurers = [
        ('RE01','慕尼黑再保险','123456789','德国','AAA','2000-01-01'),
        ('RE02','瑞士再保险','987654321','瑞士','AAA','2001-02-01'),
        ('RE03','中国再保险','567891234','中国','AA','2003-03-01'),
    ]
    data = []
    for i in range(min(n, len(reinsurers))):
        row = {
            'reinsurer_id': reinsurers[i][0],
            'reinsurer_name': reinsurers[i][1],
            'credit_code': reinsurers[i][2],
            'country': reinsurers[i][3],
            'credit_rating': reinsurers[i][4],
            'cooperation_start': reinsurers[i][5],
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_treaty_contract(n):
    data = []
    for i in range(min(n, 5)):  # 合约数较少
        row = {
            'treaty_id': generate_id('TR', 9),
            'treaty_code': f"TREATY{i+1}",
            'reinsurer_id': random.choice(['RE01','RE02','RE03']),
            'treaty_type': random.choice(['比例','溢额']),
            'effective_date': START_DATE.strftime('%Y-%m-%d'),
            'expiry_date': END_DATE.strftime('%Y-%m-%d'),
            'lines': round(random.uniform(5, 20), 2),
            'commission_rate': round(random.uniform(0.1, 0.2), 4),
            'settlement_cycle': random.choice(['月结','季结']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_facultative_placement(n):
    data = []
    for i in range(min(n, len(policy_ids)//20)):
        row = {
            'placement_id': generate_id('FP', 9),
            'policy_id': random.choice(policy_ids),
            'reinsurer_id': random.choice(['RE01','RE02','RE03']),
            'placement_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'share_ratio': round(random.uniform(0.1, 0.5), 4),
            'premium_ceded': round(random.uniform(1000, 50000), 2),
            'commission_rate': round(random.uniform(0.05, 0.15), 4),
            'approval_status': random.choice(['已批','待批']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

def generate_fact_reinsurance_recovery(n):
    data = []
    for i in range(min(n, len(claim_ids)//20)):
        row = {
            'recovery_id': generate_id('RR', 9),
            'claim_id': random.choice(claim_ids),
            'treaty_id': random.choice([f"TR{random.randint(10000,99999)}" for _ in range(1)]),
            'recovery_date': random_date(START_DATE, END_DATE).strftime('%Y-%m-%d'),
            'recovery_amount': round(random.uniform(1000, 20000), 2),
            'recovery_status': random.choice(['已摊回','待摊回']),
            'etl_time': 'current_timestamp()',
            'dt': f"'{PARTITION_DT}'"
        }
        data.append(row)
    return data

# ==================== 主生成逻辑 ====================
def write_insert(f, table_name, columns, data_list):
    if not data_list:
        return
    # 构建INSERT语句模板
    cols_str = ', '.join(columns)
    values_template = '(' + ', '.join(['%s'] * len(columns)) + ')'
    f.write(f"INSERT INTO {table_name} ({cols_str}) VALUES\n")
    rows = []
    for row in data_list:
        # 将值转换为字符串，处理None和引号
        vals = []
        for col in columns:
            val = row[col]
            if val is None or val == 'NULL':
                vals.append('NULL')
            elif isinstance(val, str):
                # 如果是字符串且不是函数调用（如current_timestamp()），加单引号
                if val.startswith('current_timestamp') or val == 'NULL':
                    vals.append(val)
                else:
                    # 转义单引号
                    val_escaped = val.replace("'", "''")
                    vals.append(f"'{val_escaped}'")
            elif isinstance(val, (int, float)):
                vals.append(str(val))
            else:
                vals.append(str(val))
        rows.append('(' + ', '.join(vals) + ')')
    f.write(',\n'.join(rows))
    f.write(';\n\n')

def main():
    # 先生成所有表数据（存储为列表）
    print("生成数据中...")
    data = {}

    # 维度表（需要先生成以供引用）
    data['dim_customer_individual'] = generate_dim_customer_individual(ROW_COUNT_PER_TABLE)
    data['dim_customer_enterprise'] = generate_dim_customer_enterprise(ROW_COUNT_PER_TABLE)
    data['dim_customer_contact'] = generate_dim_customer_contact(ROW_COUNT_PER_TABLE)
    data['dim_customer_relation'] = generate_dim_customer_relation(ROW_COUNT_PER_TABLE)
    data['dim_customer_address'] = generate_dim_customer_address(ROW_COUNT_PER_TABLE)
    data['dim_customer_vehicle'] = generate_dim_customer_vehicle(ROW_COUNT_PER_TABLE)
    data['dim_customer_property'] = generate_dim_customer_property(ROW_COUNT_PER_TABLE)
    data['fact_customer_score'] = generate_fact_customer_score(ROW_COUNT_PER_TABLE)

    data['dim_product_line'] = generate_dim_product_line(ROW_COUNT_PER_TABLE)
    data['dim_product'] = generate_dim_product(ROW_COUNT_PER_TABLE)
    data['dim_coverage'] = generate_dim_coverage(ROW_COUNT_PER_TABLE)
    data['dim_rate_factor'] = generate_dim_rate_factor(ROW_COUNT_PER_TABLE)
    data['fact_rate_table'] = generate_fact_rate_table(ROW_COUNT_PER_TABLE)
    data['dim_clause'] = generate_dim_clause(ROW_COUNT_PER_TABLE)

    data['dim_channel'] = generate_dim_channel(ROW_COUNT_PER_TABLE)
    data['dim_agent'] = generate_dim_agent(ROW_COUNT_PER_TABLE)
    data['dim_agency'] = generate_dim_agency(ROW_COUNT_PER_TABLE)
    data['fact_commission_rule'] = generate_fact_commission_rule(ROW_COUNT_PER_TABLE)

    # 事实表（依赖上述ID）
    data['fact_application'] = generate_fact_application(ROW_COUNT_PER_TABLE)
    data['dim_application_item'] = generate_dim_application_item(ROW_COUNT_PER_TABLE)
    data['fact_policy'] = generate_fact_policy(ROW_COUNT_PER_TABLE)
    data['dim_policy_item'] = generate_dim_policy_item(ROW_COUNT_PER_TABLE)
    data['dim_policy_insured'] = generate_dim_policy_insured(ROW_COUNT_PER_TABLE)
    data['dim_policy_beneficiary'] = generate_dim_policy_beneficiary(ROW_COUNT_PER_TABLE)
    data['dim_policy_vehicle'] = generate_dim_policy_vehicle(ROW_COUNT_PER_TABLE)
    data['dim_policy_property'] = generate_dim_policy_property(ROW_COUNT_PER_TABLE)
    data['fact_endorsement'] = generate_fact_endorsement(ROW_COUNT_PER_TABLE)
    data['dim_endorsement_item'] = generate_dim_endorsement_item(ROW_COUNT_PER_TABLE)
    data['fact_coinsurance'] = generate_fact_coinsurance(ROW_COUNT_PER_TABLE)
    data['fact_treaty_reinsurance'] = generate_fact_treaty_reinsurance(ROW_COUNT_PER_TABLE)
    data['fact_facultative_reinsurance'] = generate_fact_facultative_reinsurance(ROW_COUNT_PER_TABLE)
    data['dim_risk_unit'] = generate_dim_risk_unit(ROW_COUNT_PER_TABLE)
    data['fact_policy_status_history'] = generate_fact_policy_status_history(ROW_COUNT_PER_TABLE)

    data['fact_report'] = generate_fact_report(ROW_COUNT_PER_TABLE)
    data['dim_accident'] = generate_dim_accident(ROW_COUNT_PER_TABLE)
    data['fact_survey'] = generate_fact_survey(ROW_COUNT_PER_TABLE)
    data['fact_loss_assessment'] = generate_fact_loss_assessment(ROW_COUNT_PER_TABLE)
    data['dim_loss_item'] = generate_dim_loss_item(ROW_COUNT_PER_TABLE)
    data['fact_claim'] = generate_fact_claim(ROW_COUNT_PER_TABLE)
    data['fact_recovery'] = generate_fact_recovery(ROW_COUNT_PER_TABLE)
    data['dim_injury_case'] = generate_dim_injury_case(ROW_COUNT_PER_TABLE)
    data['dim_third_party'] = generate_dim_third_party(ROW_COUNT_PER_TABLE)
    data['fact_reserve'] = generate_fact_reserve(ROW_COUNT_PER_TABLE)
    data['fact_fraud_alert'] = generate_fact_fraud_alert(ROW_COUNT_PER_TABLE)
    data['fact_claim_status_history'] = generate_fact_claim_status_history(ROW_COUNT_PER_TABLE)

    data['fact_premium_payment'] = generate_fact_premium_payment(ROW_COUNT_PER_TABLE)
    data['fact_claim_payment'] = generate_fact_claim_payment(ROW_COUNT_PER_TABLE)
    data['fact_commission_settlement'] = generate_fact_commission_settlement(ROW_COUNT_PER_TABLE)
    data['fact_account_receivable'] = generate_fact_account_receivable(ROW_COUNT_PER_TABLE)
    data['fact_account_payable'] = generate_fact_account_payable(ROW_COUNT_PER_TABLE)
    data['fact_premium_income'] = generate_fact_premium_income(ROW_COUNT_PER_TABLE)
    data['fact_incurred_loss'] = generate_fact_incurred_loss(ROW_COUNT_PER_TABLE)
    data['fact_reserve_ledger'] = generate_fact_reserve_ledger(ROW_COUNT_PER_TABLE)

    data['dim_reinsurer'] = generate_dim_reinsurer(ROW_COUNT_PER_TABLE)
    data['fact_treaty_contract'] = generate_fact_treaty_contract(ROW_COUNT_PER_TABLE)
    data['fact_facultative_placement'] = generate_fact_facultative_placement(ROW_COUNT_PER_TABLE)
    data['fact_reinsurance_recovery'] = generate_fact_reinsurance_recovery(ROW_COUNT_PER_TABLE)

    # 写入文件
    print(f"写入文件 {OUTPUT_FILE} ...")
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        # 可选的设置（如SET语句）
        f.write("-- 财产险业务数据平台 INSERT 语句\n")
        f.write(f"-- 生成日期: {datetime.datetime.now()}\n")
        f.write(f"-- 每表行数: {ROW_COUNT_PER_TABLE}\n\n")

        # 按依赖顺序写入（先维度表，后事实表）
        order = [
            'dim_customer_individual',
            'dim_customer_enterprise',
            'dim_customer_contact',
            'dim_customer_relation',
            'dim_customer_address',
            'dim_customer_vehicle',
            'dim_customer_property',
            'fact_customer_score',
            'dim_product_line',
            'dim_product',
            'dim_coverage',
            'dim_rate_factor',
            'fact_rate_table',
            'dim_clause',
            'dim_channel',
            'dim_agent',
            'dim_agency',
            'fact_commission_rule',
            'fact_application',
            'dim_application_item',
            'fact_policy',
            'dim_policy_item',
            'dim_policy_insured',
            'dim_policy_beneficiary',
            'dim_policy_vehicle',
            'dim_policy_property',
            'fact_endorsement',
            'dim_endorsement_item',
            'fact_coinsurance',
            'fact_treaty_reinsurance',
            'fact_facultative_reinsurance',
            'dim_risk_unit',
            'fact_policy_status_history',
            'fact_report',
            'dim_accident',
            'fact_survey',
            'fact_loss_assessment',
            'dim_loss_item',
            'fact_claim',
            'fact_recovery',
            'dim_injury_case',
            'dim_third_party',
            'fact_reserve',
            'fact_fraud_alert',
            'fact_claim_status_history',
            'fact_premium_payment',
            'fact_claim_payment',
            'fact_commission_settlement',
            'fact_account_receivable',
            'fact_account_payable',
            'fact_premium_income',
            'fact_incurred_loss',
            'fact_reserve_ledger',
            'dim_reinsurer',
            'fact_treaty_contract',
            'fact_facultative_placement',
            'fact_reinsurance_recovery'
        ]

        for table in order:
            if table in data and data[table]:
                # 获取列名（从data的第一行）
                columns = list(data[table][0].keys())
                write_insert(f, table, columns, data[table])
            else:
                print(f"警告: 表 {table} 无数据")

    print(f"完成！生成文件 {OUTPUT_FILE}")

if __name__ == '__main__':
    main()