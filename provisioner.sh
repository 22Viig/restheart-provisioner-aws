#!/bin/bash

RESTHEART_CLUSTER_NAME="rh-cluster-test"

# create VPC
RH_VPC_ID=$(aws ec2 create-vpc --region eu-west-1 --cidr-block 10.0.0.0/16 | jq '.Vpc.VpcId' -r)

echo "VPC Created, ID: ${RH_VPC_ID}"

# create Subnet 1
RH_SUBNET_1_ID=$(aws ec2 create-subnet --region eu-west-1 --availability-zone eu-west-1a --vpc-id ${RH_VPC_ID} --cidr-block 10.0.0.0/24 | jq '.Subnet.SubnetId' -r)

# create Subnet 2
RH_SUBNET_2_ID=$(aws ec2 create-subnet --region eu-west-1 --availability-zone eu-west-1b --vpc-id ${RH_VPC_ID} --cidr-block 10.0.1.0/24 | jq '.Subnet.SubnetId' -r)

echo "SUBNETS Created, ID1 : ${RH_SUBNET_1_ID}, ID2 : ${RH_SUBNET_2_ID}"

# create Internet Gateway
IG_ID=$(aws ec2 create-internet-gateway | jq '.InternetGateway.InternetGatewayId' -r)

echo "Internet Gateway Created, ID1 : ${IG_ID}"

# attach IG to VPC
aws ec2 attach-internet-gateway --internet-gateway-id ${IG_ID} --vpc-id ${RH_VPC_ID}


# craete Routes
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${RH_VPC_ID}" | jq '.RouteTables[0].RouteTableId' -r)

aws ec2 create-route --route-table-id ${ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0  --gateway-id ${IG_ID}

aws ec2 associate-route-table --route-table-id ${ROUTE_TABLE_ID} --subnet-id ${RH_SUBNET_1_ID}
aws ec2 associate-route-table --route-table-id ${ROUTE_TABLE_ID} --subnet-id ${RH_SUBNET_2_ID}


# configure ECS Cluster
ecs-cli configure --cluster $RESTHEART_CLUSTER_NAME --default-launch-type FARGATE --config-name $RESTHEART_CLUSTER_NAME --region eu-west-1

# create ECS Cluster
ecs-cli up --cluster-config $RESTHEART_CLUSTER_NAME --vpc $RH_VPC_ID --subnets $RH_SUBNET_1_ID, $RH_SUBNET_2_ID --region eu-west-1 --force

# create Security Group
SECURITY_GROUP_ID=$(aws ec2 create-security-group --description rh-cluster-security-group --group-name rh-cluster-security-group --vpc-id ${RH_VPC_ID} | jq '.GroupId' -r)

echo "Security Group Created, id: ${SECURITY_GROUP_ID}"

aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --protocol tcp --port 8080 --cidr 0.0.0.0/0 --region eu-west-1

# create Role Policy
aws iam --region eu-west-1 create-role --role-name RHClusterTaskExecutionRole --assume-role-policy-document file://assume_role_policy.json

aws iam --region eu-west-1 attach-role-policy --role-name RHClusterTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# replace text with subnets and security group in ecs-params.yml file
sed -i "" "s/<SUBNET_1_ID>/${RH_SUBNET_1_ID}/g" ecs-params.yml
sed -i "" "s/<SUBNET_2_ID>/${RH_SUBNET_2_ID}/g" ecs-params.yml
sed -i "" "s/<SECURITY_GROUP_ID>/${SECURITY_GROUP_ID}/g" ecs-params.yml

# create Load Balancer
aws elb create-load-balancer --load-balancer-name ${RESTHEART_CLUSTER_NAME}-alb --listeners "Protocol=HTTP,LoadBalancerPort=8080,InstanceProtocol=HTTP,InstancePort=8080" --subnets ${RH_SUBNET_1_ID} ${RH_SUBNET_2_ID} --security-groups ${SECURITY_GROUP_ID} 

# deploy docker-compose file
ecs-cli compose --project-name ${RESTHEART_CLUSTER_NAME} service up --create-log-groups --cluster-config ${RESTHEART_CLUSTER_NAME} --region eu-west-1

# --load-balancer-name ${RESTHEART_CLUSTER_NAME}-alb --container-name resheart --container-port 8080 --target-group-arn

# check the cluster status
ecs-cli compose --project-name ${RESTHEART_CLUSTER_NAME} service ps --cluster-config ${RESTHEART_CLUSTER_NAME}








