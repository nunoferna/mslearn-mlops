# Import libraries

import argparse
import glob
import os

import pandas as pd
import mlflow
import mlflow.sklearn

from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split


# define functions
def main(args):
    # Azure ML currently supports MLflow 2.16 and earlier for model logging.
    # Explicit metric logging avoids newer LoggedModels API calls from MLflow 3.x.
    mlflow.autolog(log_models=False)

    # read data
    df = get_csvs_df(args.training_data)

    # split data
    X_train, X_test, y_train, y_test = split_data(df)

    # train model
    model = train_model(args.reg_rate, X_train, X_test, y_train, y_test)

    # evaluate model
    evaluate_model(model, X_test, y_test)

    # save model
    save_model(model, args.model_output)


def get_csvs_df(path):
    if not os.path.exists(path):
        raise RuntimeError(f"Cannot use non-existent path provided: {path}")
    csv_files = glob.glob(f"{path}/*.csv")
    if not csv_files:
        raise RuntimeError(f"No CSV files found in provided data path: {path}")
    return pd.concat((pd.read_csv(f) for f in csv_files), sort=False)


def split_data(df):
    X, y = df[['Pregnancies', 'PlasmaGlucose',
               'DiastolicBloodPressure', 'TricepsThickness', 'SerumInsulin',
               'BMI', 'DiabetesPedigree', 'Age']].values, df['Diabetic'].values
    return train_test_split(X, y, test_size=0.30, random_state=0)


def train_model(reg_rate, X_train, X_test, y_train, y_test):
    # train model
    mlflow.log_param("Regularization rate", reg_rate)
    return LogisticRegression(C=1/reg_rate, solver="liblinear").fit(X_train, y_train)


def evaluate_model(model, X_test, y_test):
    y_hat = model.predict(X_test)
    acc = (y_hat == y_test).mean()
    print("Accuracy:", acc)
    mlflow.log_metric("Accuracy", acc)

    y_scores = model.predict_proba(X_test)
    auc = roc_auc_score(y_test, y_scores[:, 1])
    print("AUC:", auc)
    mlflow.log_metric("AUC", auc)


def save_model(model, model_output):
    print(f"Saving model to {model_output}")
    os.makedirs(model_output, exist_ok=True)
    mlflow.sklearn.save_model(model, model_output)


def parse_args():
    # setup arg parser
    parser = argparse.ArgumentParser()

    # add arguments
    parser.add_argument("--training_data", dest='training_data',
                        type=str)
    parser.add_argument("--reg_rate", dest='reg_rate',
                        type=float, default=0.01)
    parser.add_argument("--model_output", dest='model_output',
                        type=str)

    # parse args
    args = parser.parse_args()

    # return args
    return args


# run script
if __name__ == "__main__":
    # add space in logs
    print("\n\n")
    print("*" * 60)

    # parse args
    args = parse_args()

    # run main function
    main(args)

    # add space in logs
    print("*" * 60)
    print("\n\n")
