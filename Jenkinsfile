pipeline {
    agent any

    environment {
        DOCKER_NS = 'charlesphan66'
        STAGING = 'ec2-user@172.31.90.253'
        STAGING_URL = 'http://172.31.90.253:8081'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
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
                    junit allowEmptyResults: false, testResults: 'reports/*.xml'
                }
            }
        }

        stage('Push Images') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub',
                    usernameVariable: 'U', passwordVariable: 'P')]) {
                        sh """
                            echo "\$P" | docker login -u "\$U" --password-stdin
                            docker tag rmit-api:${env.SHA} ${DOCKER_NS}/rmit-api:${env.SHA}
                            docker tag rmit-client:${env.SHA} ${DOCKER_NS}/rmit-client:${env.SHA}
                            docker push ${DOCKER_NS}/rmit-api:${env.SHA}
                            docker push ${DOCKER_NS}/rmit-client:${env.SHA}
                            docker logout
                        """
                    }
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
            emailText(
                subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.SHA})",
                body: """Build failed at stage: ${env.STAGE_NAME}

Commit: ${env.SHA}
Log: ${env.BUILD_URL}console

Production not touched. Staging may be broken. Please check the staging server at ${STAGING_URL}.
                """,
                to: '$DEFAULT_RECIPIENTS',
                attachLog: true
            )
        }
        fixed {
            emailText(
                subject: "RECOVERED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Pipeline is recovered to commit ${env.SHA}. \n${env.BUILD_URL}",
                to: '$DEFAULT_RECIPIENTS',
            )
        }
    }
}