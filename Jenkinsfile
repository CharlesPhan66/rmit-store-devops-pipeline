pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        ECR = '222431607375.dkr.ecr.us-east-1.amazonaws.com'
        STAGING = 'ec2-user@172.31.90.253'
        STAGING_URL = 'http://172.31.90.253:8081'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'rm -rf reports && mkdir -p reports'
                script {
                    env.SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                }
                echo "Building commit ${env.SHA}"
            }
        }

        stage('Build images') {
            steps {
                sh """
                    docker build -f docker/api.Dockerfile --target runtime \
                        --build-arg GIT_COMMIT=${env.SHA} \
                        -t rmit-api:${env.SHA} .
                    docker build -f docker/client.Dockerfile \
                        -t rmit-client:${env.SHA} .
                """
            }
        }

        stage('Test') {
            steps {
                sh "docker build -f docker/api.Dockerfile --target test -t rmit-api:test-${env.SHA} ."
                sh "mkdir -p reports"
                sh """
                    docker network create ci-${env.BUILD_NUMBER} || true
                    docker run -d --name ci-db-${env.BUILD_NUMBER} \
                        --network ci-${env.BUILD_NUMBER} \
                        -e POSTGRES_USER=rmit \
                        -e POSTGRES_PASSWORD=rmit \
                        -e POSTGRES_DB=rmit_store \
                        postgres:16-alpine
                    sleep 10
                    docker run --rm --network ci-${env.BUILD_NUMBER} \
                        -e DATABASE_URL=postgres://rmit:rmit@ci-db-${env.BUILD_NUMBER}:5432/rmit_store \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} pytest -m "unit or integration" \
                        --junitxml=reports/backend.xml
                """
            }
            post {
                always {
                    sh """
                        docker rm -f ci-db-${env.BUILD_NUMBER} || true
                        docker network rm ci-${env.BUILD_NUMBER} || true
                    """
                    junit allowEmptyResults: false, testResults: 'reports/backend.xml'
                }
            }
        }

        stage('Push Images') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} \
                        | docker login --username AWS --password-stdin ${ECR}
                    
                    docker tag rmit-api:${env.SHA} ${ECR}/rmit-api:${env.SHA}
                    docker tag rmit-client:${env.SHA} ${ECR}/rmit-client:${env.SHA}

                    docker push ${ECR}/rmit-api:${env.SHA}
                    docker push ${ECR}/rmit-client:${env.SHA}
                """
            }
        }

        stage('Deploy Staging') {
            steps {
                sshagent(['app-host-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${STAGING} \
                            'GIT_SHA=${env.SHA} ~/deploy.sh'
                    """
                }
            }
        }

        stage('Smoke staging') {
            steps {
                sh """
                    docker run --rm --network host \
                        -e BASE_URL=${STAGING_URL} \
                        -e GIT_SHA=${env.SHA} \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} pytest tests/smoke --junitxml=reports/smoke.xml
                """
            }
            post {
                always {
                    junit 'reports/smoke.xml'
                }
            }
        }
    }

    post {
        failure {
            emailext(
                subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.SHA})",
                body: """Build failed at stage: ${env.STAGE_NAME}

Commit: ${env.SHA}
Log: ${env.BUILD_URL}console

Production not touched.
                """,
                to: '$DEFAULT_RECIPIENTS',
            )
        }
        unstable {
            emailext(
                subject: "UNSTABLE: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.SHA})",
                body: """Build unstable at stage: ${env.STAGE_NAME}
Commit: ${env.SHA}
Log: ${env.BUILD_URL}console coverage may be low. Staging may be broken.
                """,
                to: '$DEFAULT_RECIPIENTS',
            )
        }
        fixed {
            emailext(
                subject: "RECOVERED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Pipeline is recovered to commit ${env.SHA}. \n${env.BUILD_URL}",
                to: '$DEFAULT_RECIPIENTS',
            )
        }
    }
}