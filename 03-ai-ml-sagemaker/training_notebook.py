"""
LEVEL UP IN TECH - AI/ML ENGINEER LAB
Training Notebook: Fraud Detection Model

Run this script in a SageMaker notebook or locally with boto3 configured.
It will:
  1. Generate synthetic fraud detection training data
  2. Upload it to your S3 bucket
  3. Train an XGBoost model via SageMaker
  4. Upload the model artifact to S3
  5. Then you can deploy the endpoint with: terraform apply -var="deploy_endpoint=true"

PREREQUISITES:
  - pip install boto3 pandas scikit-learn sagemaker
  - AWS credentials configured
  - Terraform infrastructure already deployed (S3 buckets, IAM role exist)
"""

import boto3
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.datasets import make_classification
import sagemaker
from sagemaker import image_uris
from sagemaker.inputs import TrainingInput
import json
import os

# ─── Configuration ───
PROJECT_NAME = "luit-ml-lab"  # Must match your terraform project_name
REGION = "us-east-1"          # Must match your terraform aws_region

# Get account ID
sts = boto3.client('sts')
ACCOUNT_ID = sts.get_caller_identity()['Account']

DATA_BUCKET = f"{PROJECT_NAME}-data-{ACCOUNT_ID}"
MODELS_BUCKET = f"{PROJECT_NAME}-models-{ACCOUNT_ID}"

print(f"Account: {ACCOUNT_ID}")
print(f"Data bucket: {DATA_BUCKET}")
print(f"Models bucket: {MODELS_BUCKET}")


# ─── Step 1: Generate Synthetic Fraud Data ───
print("\n=== Step 1: Generating synthetic fraud data ===")

np.random.seed(42)

# Generate base features
n_samples = 50000
X, y = make_classification(
    n_samples=n_samples,
    n_features=10,
    n_informative=7,
    n_redundant=2,
    n_classes=2,
    weights=[0.95, 0.05],  # 5% fraud rate
    random_state=42
)

# Create realistic feature names
feature_names = [
    'transaction_amount', 'merchant_category', 'time_since_last_txn',
    'device_type', 'geo_distance', 'card_present',
    'transaction_hour', 'day_of_week', 'velocity_1h', 'avg_txn_amount'
]

df = pd.DataFrame(X, columns=feature_names)
df['is_fraud'] = y

# Make features more realistic
df['transaction_amount'] = np.abs(df['transaction_amount']) * 100 + 10
df['merchant_category'] = np.abs(df['merchant_category']).astype(int) % 20
df['time_since_last_txn'] = np.abs(df['time_since_last_txn']) * 3600
df['device_type'] = np.abs(df['device_type']).astype(int) % 4
df['geo_distance'] = np.abs(df['geo_distance']) * 50
df['card_present'] = (df['card_present'] > 0).astype(int)
df['transaction_hour'] = np.abs(df['transaction_hour']).astype(int) % 24
df['day_of_week'] = np.abs(df['day_of_week']).astype(int) % 7
df['velocity_1h'] = np.abs(df['velocity_1h']).astype(int) + 1
df['avg_txn_amount'] = np.abs(df['avg_txn_amount']) * 80 + 20

print(f"Generated {len(df)} records")
print(f"Fraud rate: {df['is_fraud'].mean():.2%}")
print(f"Features: {feature_names}")


# ─── Step 2: Prepare and Upload Training Data ───
print("\n=== Step 2: Uploading training data to S3 ===")

# SageMaker XGBoost expects: label as first column, no header
train_df, val_df = train_test_split(df, test_size=0.2, stratify=df['is_fraud'], random_state=42)

# Reorder columns: label first
cols = ['is_fraud'] + feature_names
train_df = train_df[cols]
val_df = val_df[cols]

# Save locally
train_df.to_csv('/tmp/train.csv', index=False, header=False)
val_df.to_csv('/tmp/validation.csv', index=False, header=False)

# Also save with headers for later analysis
df.to_csv('/tmp/full_data_with_headers.csv', index=False)

# Upload to S3
s3 = boto3.client('s3')
s3.upload_file('/tmp/train.csv', DATA_BUCKET, 'training/train.csv')
s3.upload_file('/tmp/validation.csv', DATA_BUCKET, 'training/validation.csv')
s3.upload_file('/tmp/full_data_with_headers.csv', DATA_BUCKET, 'training/full_data.csv')

print(f"Training data: s3://{DATA_BUCKET}/training/train.csv ({len(train_df)} records)")
print(f"Validation data: s3://{DATA_BUCKET}/training/validation.csv ({len(val_df)} records)")


# ─── Step 3: Generate "Drifted" Production Data ───
print("\n=== Step 3: Generating drifted production data ===")

# Create production data with drift (simulates 3 months of change)
np.random.seed(99)
n_prod = 10000
X_prod, y_prod = make_classification(
    n_samples=n_prod, n_features=10, n_informative=7,
    n_redundant=2, n_classes=2, weights=[0.93, 0.07],
    random_state=99
)

prod_df = pd.DataFrame(X_prod, columns=feature_names)
prod_df['is_fraud'] = y_prod

# Apply drift: transaction amounts shifted up 35%
prod_df['transaction_amount'] = np.abs(prod_df['transaction_amount']) * 135 + 15

# Apply drift: new device type (5) that didn't exist in training
prod_df['device_type'] = np.abs(prod_df['device_type']).astype(int) % 6  # Now 0-5 instead of 0-3

# Keep other features similar
prod_df['merchant_category'] = np.abs(prod_df['merchant_category']).astype(int) % 20
prod_df['time_since_last_txn'] = np.abs(prod_df['time_since_last_txn']) * 3600
prod_df['geo_distance'] = np.abs(prod_df['geo_distance']) * 50
prod_df['card_present'] = (prod_df['card_present'] > 0).astype(int)
prod_df['transaction_hour'] = np.abs(prod_df['transaction_hour']).astype(int) % 24
prod_df['day_of_week'] = np.abs(prod_df['day_of_week']).astype(int) % 7
prod_df['velocity_1h'] = np.abs(prod_df['velocity_1h']).astype(int) + 1
prod_df['avg_txn_amount'] = np.abs(prod_df['avg_txn_amount']) * 80 + 20

prod_df.to_csv('/tmp/production_data.csv', index=False)
s3.upload_file('/tmp/production_data.csv', DATA_BUCKET, 'production/last_30_days.csv')

# Create labeled subset (simulates fraud team labeling with 48-hour delay)
labeled = prod_df.sample(n=3000, random_state=42)
labeled.to_csv('/tmp/labeled_recent.csv', index=False)
s3.upload_file('/tmp/labeled_recent.csv', DATA_BUCKET, 'production/labeled_last_14_days.csv')

print(f"Production data: s3://{DATA_BUCKET}/production/last_30_days.csv ({len(prod_df)} records)")
print(f"Labeled recent: s3://{DATA_BUCKET}/production/labeled_last_14_days.csv ({len(labeled)} records)")
print(f"Drift applied: transaction_amount +35%, new device_type=5")


# ─── Step 4: Train the Model ───
print("\n=== Step 4: Training XGBoost model via SageMaker ===")

session = sagemaker.Session()
role_arn = f"arn:aws:iam::{ACCOUNT_ID}:role/{PROJECT_NAME}-sagemaker-exec"

container = image_uris.retrieve('xgboost', REGION, '1.5-1')
print(f"Container: {container}")
print(f"Role: {role_arn}")

estimator = sagemaker.estimator.Estimator(
    image_uri=container,
    role=role_arn,
    instance_count=1,
    instance_type='ml.m5.xlarge',
    output_path=f's3://{MODELS_BUCKET}/model/',
    sagemaker_session=session,
    hyperparameters={
        'objective': 'binary:logistic',
        'num_round': 150,
        'max_depth': 5,
        'eta': 0.1,
        'min_child_weight': 5,
        'subsample': 0.8,
        'scale_pos_weight': 10,
        'eval_metric': 'auc'
    }
)

train_input = TrainingInput(
    f's3://{DATA_BUCKET}/training/train.csv',
    content_type='text/csv'
)
val_input = TrainingInput(
    f's3://{DATA_BUCKET}/training/validation.csv',
    content_type='text/csv'
)

print("Starting training job... (this takes 5-10 minutes)")
estimator.fit({'train': train_input, 'validation': val_input})

print(f"\nModel artifact: {estimator.model_data}")
print("\n=== Training complete! ===")
print(f"\nNext step: Run 'terraform apply -var=\"deploy_endpoint=true\"' to deploy the endpoint.")
print("Then use the simulation guide to troubleshoot the intentionally broken infrastructure.")
