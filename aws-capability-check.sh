#!/bin/bash
set -e

NETWORK_STACK="rmit-store-network"
DATA_STACK="rmit-store-data"
COMPUTE_STACK="rmit-store-compute"
REGION=$(aws configure get region || echo "us-east-1")

# 1. Validate templates
aws cloudformation validate-template --template-body file://cloudformation/01-network.yml
aws cloudformation validate-template --template-body file://cloudformation/02-data.yml
aws cloudformation validate-template --template-body file://cloudformation/03-compute.yml

# 2. Deploy network stack
aws cloudformation deploy \
  --stack-name ${NETWORK_STACK} \
  --template-file cloudformation/01-network.yml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region ${REGION}

# 3. Generate dynamic Django secret key
DJANGO_SECRET=$(python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())" 2>/dev/null || openssl rand -base64 32)

# 4. Deploy data stack
aws cloudformation deploy \
  --stack-name ${DATA_STACK} \
  --template-file cloudformation/02-data.yml \
  --parameter-overrides \
    NetworkStackName=${NETWORK_STACK} \
    DBPassword="RmitStore2767Pass!" \
    DjangoSecretKey="${DJANGO_SECRET}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region ${REGION}

# 5. Deploy compute stack
aws cloudformation deploy \
  --stack-name ${COMPUTE_STACK} \
  --template-file cloudformation/03-compute.yml \
  --parameter-overrides \
    NetworkStackName=${NETWORK_STACK} \
    DataStackName=${DATA_STACK} \
    KeyPairName=devops_project_key \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region ${REGION}

# 6. Retrieve outputs
aws cloudformation describe-stacks --stack-name ${COMPUTE_STACK} --query "Stacks[0].Outputs" --output table --region ${REGION}

# 7. Verify S3 media bucket accessibility
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name ${DATA_STACK} --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" --output text --region ${REGION})

# 8. Upload a test asset and verify anonymous browser read access
echo "RMIT Store Asset Check" > test-asset.txt
aws s3 cp test-asset.txt s3://${BUCKET_NAME}/test-asset.txt --region ${REGION}
curl -I -L "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/test-asset.txt"
rm -f test-asset.txt

# 9. Verify SSM parameters
aws ssm get-parameters-by-path --path "/rmit-store" --recursive --query "Parameters[*].[Name,Value]" --output table --region ${REGION}

# 10. Verify private RDS network
RDS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name ${DATA_STACK} --query "Stacks[0].Outputs[?OutputKey=='RDSEndpoint'].OutputValue" --output text --region ${REGION})

# 11. Probing from local machine must timeout (verifies database is unreachable from the public internet)
nc -zv -w 3 ${RDS_ENDPOINT} 5432 || echo "Verified: RDS is private and blocked from the internet"