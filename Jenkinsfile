pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    stages {

        stage('Resolve environment') {
            steps {
                script {
                    env.CURRENT_STAGE = 'Resolve environment'
                    def ssm = { name ->
                        sh(script: "aws ssm get-parameter --name ${name} --query Parameter.Value --output text", returnStdout: true).trim()
                    }
                    env.AWS_REGION  = 'us-east-1'
                    env.ECR         = ssm('/rmit/ECR_REGISTRY')
                    env.STAGING     = "ec2-user@" + ssm('/rmit/staging/PRIVATE_IP')
                    env.STAGING_URL = "http://" + ssm('/rmit/staging/PRIVATE_IP') + ":8081"
                    env.SWARM_MGR   = "ec2-user@" + ssm('/rmit/prod/SWARM_MGR_IP')
                    env.PROD_URL    = "http://" + ssm('/rmit/prod/ALB_DNS')
                    echo "ecr=${env.ECR} staging=${env.STAGING_URL} prod=${env.PROD_URL}"
                }
            }
        }

        stage('Checkout') {
            steps {
                script { env.CURRENT_STAGE = 'Checkout' }
                checkout scm
                sh 'rm -rf test-reports && mkdir -p test-reports'
                script {
                    env.SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                }
                echo "Building commit ${env.SHA}"
            }
        }

        stage('Build images') {
            steps {
                script { env.CURRENT_STAGE = 'Build images' }
                sh """
                    docker build -t rmit-api:${env.SHA} app/server
                    docker build -t rmit-client:${env.SHA} app/client
                """
            }
        }

        stage('Backend tests') {
            steps {
                script { env.CURRENT_STAGE = 'Backend tests' }
                sh """
                    docker network create ci-${env.BUILD_NUMBER} || true
                    docker run -d --name ci-db-${env.BUILD_NUMBER} \\
                        --network ci-${env.BUILD_NUMBER} \\
                        -e POSTGRES_USER=rmit \\
                        -e POSTGRES_PASSWORD=rmit \\
                        -e POSTGRES_DB=rmit_store \\
                        postgres:16

                    echo 'Waiting for test database to accept connections...'
                    for i in \$(seq 1 15); do
                        docker exec ci-db-${env.BUILD_NUMBER} pg_isready -U rmit && break
                        sleep 2
                    done

                    docker run --rm --network ci-${env.BUILD_NUMBER} \\
                        -e DATABASE_URL=postgres://rmit:rmit@ci-db-${env.BUILD_NUMBER}:5432/rmit_store \\
                        -e SECRET_KEY=jenkins-test-key \\
                        -e ALLOWED_HOSTS=localhost,127.0.0.1 \\
                        -e DJANGO_SETTINGS_MODULE=ci_test_settings \\
                        -v "\$(pwd)/test-reports:/app/test-reports" \\
                        --entrypoint sh rmit-api:${env.SHA} \\
                        -c "pip install --quiet unittest-xml-reporting && python manage.py test apps.orders apps.catalog apps.core"
                """
            }
            post {
                always {
                    sh """
                        docker rm -f ci-db-${env.BUILD_NUMBER} || true
                        docker network rm ci-${env.BUILD_NUMBER} || true
                    """
                    junit allowEmptyResults: false, testResults: 'test-reports/*.xml'
                }
            }
        }

        stage('Frontend E2E tests') {
            steps {
                script { env.CURRENT_STAGE = 'Frontend E2E tests' }
                sh """
                    docker network create ci-e2e-${env.BUILD_NUMBER} || true

                    docker run -d --name ci-e2e-db-${env.BUILD_NUMBER} \\
                        --network ci-e2e-${env.BUILD_NUMBER} \\
                        -e POSTGRES_USER=rmit \\
                        -e POSTGRES_PASSWORD=rmit \\
                        -e POSTGRES_DB=rmit_store \\
                        postgres:16

                    echo 'Waiting for e2e database to accept connections...'
                    for i in \$(seq 1 15); do
                        docker exec ci-e2e-db-${env.BUILD_NUMBER} pg_isready -U rmit && break
                        sleep 2
                    done

                    docker run -d --name ci-e2e-api-${env.BUILD_NUMBER} \\
                        --network ci-e2e-${env.BUILD_NUMBER} \\
                        -e DATABASE_URL=postgres://rmit:rmit@ci-e2e-db-${env.BUILD_NUMBER}:5432/rmit_store \\
                        -e SECRET_KEY=jenkins-e2e-key \\
                        -e ALLOWED_HOSTS=localhost,127.0.0.1 \\
                        -e CORS_ALLOWED_ORIGINS=http://ci-e2e-frontend-${env.BUILD_NUMBER} \\
                        -e DJANGO_SETTINGS_MODULE=config.settings.dev \\
                        rmit-api:${env.SHA}

                    echo 'Waiting for API to become healthy...'
                    for i in \$(seq 1 15); do
                        docker exec ci-e2e-api-${env.BUILD_NUMBER} curl -sf http://localhost:8000/healthz/ && break
                        sleep 2
                    done

                    docker exec ci-e2e-api-${env.BUILD_NUMBER} python manage.py seed_demo \\
                        --admin-email admin@rmit.edu.au \\
                        --admin-password 'RmitStore2767!' --no-images || true

                    echo "window.__APP_CONFIG__ = { API_BASE_URL: 'http://ci-e2e-api-${env.BUILD_NUMBER}:8000/api' }" > /tmp/e2e-config-${env.BUILD_NUMBER}.js

                    docker run -d --name ci-e2e-frontend-${env.BUILD_NUMBER} \\
                        --network ci-e2e-${env.BUILD_NUMBER} \\
                        -v /tmp/e2e-config-${env.BUILD_NUMBER}.js:/usr/share/nginx/html/config.js:ro \\
                        rmit-client:${env.SHA}

                    docker run --rm --network ci-e2e-${env.BUILD_NUMBER} \\
                        -e E2E_BASE_URL=http://ci-e2e-frontend-${env.BUILD_NUMBER} \\
                        -v "\$(pwd)/app/client:/work" -w /work \\
                        mcr.microsoft.com/playwright:v1.62.1-jammy \\
                        sh -c "npm install --no-save @playwright/test && npx playwright test --config=playwright.config.js"
                """
            }
            post {
                always {
                    sh """
                        docker rm -f ci-e2e-db-${env.BUILD_NUMBER} ci-e2e-api-${env.BUILD_NUMBER} ci-e2e-frontend-${env.BUILD_NUMBER} || true
                        docker network rm ci-e2e-${env.BUILD_NUMBER} || true
                    """
                }
            }
        }


        stage('Push images') {
            steps {
                script { env.CURRENT_STAGE = 'Push images' }
                sh """
                    aws ecr get-login-password --region ${env.AWS_REGION} \\
                        | docker login --username AWS --password-stdin ${env.ECR}

                    docker tag rmit-api:${env.SHA} ${env.ECR}/rmit-api:${env.SHA}
                    docker tag rmit-client:${env.SHA} ${env.ECR}/rmit-client:${env.SHA}

                    docker push ${env.ECR}/rmit-api:${env.SHA}
                    docker push ${env.ECR}/rmit-client:${env.SHA}
                """
            }
        }

        stage('Deploy staging') {
            steps {
                script { env.CURRENT_STAGE = 'Deploy staging' }
                sshagent(['app-host-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${env.STAGING} \\
                            'GIT_SHA=${env.SHA} ~/deploy.sh'
                    """
                }
            }
        }

        stage('Smoke staging') {
            steps {
                script { env.CURRENT_STAGE = 'Smoke staging' }
                sh """
                    curl -sf ${env.STAGING_URL}/healthz/
                    curl -sf ${env.STAGING_URL}/readyz/
                """
            }
        }

        stage('Promote to production') {
            when {
                branch 'main'
            }
            steps {
                script { env.CURRENT_STAGE = 'Promote to production' }
                sshagent(['app-host-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${env.SWARM_MGR} '
                            cd ~/deploy &&
                            ECR=${env.ECR} GIT_SHA=${env.SHA} docker stack deploy \\
                                -c swarm/stack.yml --with-registry-auth rmit
                        '
                    """
                }
            }
        }

        stage('Smoke production') {
            when {
                branch 'main'
            }
            steps {
                script { env.CURRENT_STAGE = 'Smoke production' }
                sh """
                    curl -sf ${env.PROD_URL}/healthz/
                    curl -sf ${env.PROD_URL}/readyz/
                """
            }
        }
    }

    post {
        failure {
            emailext(
                subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} at ${env.CURRENT_STAGE ?: 'unknown stage'} (${env.SHA ?: 'unknown commit'})",
                body: """Build failed.

Stage: ${env.CURRENT_STAGE ?: 'unknown - failure occurred before a stage started'}
Commit: ${env.SHA ?: 'unknown - failure occurred before checkout completed'}
Log: ${env.BUILD_URL}console

Production not touched.
                """,
                to: '$DEFAULT_RECIPIENTS',
            )
        }
    }
}