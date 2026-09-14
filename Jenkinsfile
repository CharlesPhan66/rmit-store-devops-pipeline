// RMIT University Vietnam
// Course: COSC2767|COSC2805 Systems Deployment and Operations
// Semester: 2026B
// Assessment: Assignment 2
// Authors: Dang Khoa - 4058813, Le Nguyen Thanh Trung - 4123479, Charles Phan - 4131861
// Created date: 31/08/2026
// Last modified: 12/09/2026
// Acknowledgement: None

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    stages {
        // Every address comes from SSM, so rebuilding the CloudFormation stacks
        // with new IPs needs no edit here.
        stage('Resolve environment') {
            steps {
                script {
                    def ssm = { name ->
                        sh(script: "aws ssm get-parameter --name ${name} --query Parameter.Value --output text", returnStdout: true).trim()
                    }
                    def stagingIp = ssm('/rmit/staging/PRIVATE_IP')

                    env.ECR         = ssm('/rmit/ECR_REGISTRY')
                    env.STAGING     = "ec2-user@${stagingIp}"
                    env.STAGING_URL = "http://${stagingIp}:8081"
                    env.SWARM_MGR   = "ec2-user@" + ssm('/rmit/prod/SWARM_MGR_IP')

                    env.ALB_DNS      = ssm('/rmit/prod/ALB_DNS')
                    env.MEDIA_BUCKET = ssm('/rmit/prod/MEDIA_BUCKET')
                    env.PROD_URL     = "http://${env.ALB_DNS}"

                    env.EMAIL_ADDRESS = ssm('/rmit/EMAIL_ADDRESS')

                    env.AWS_REGION  = env.ECR.split('\\.')[3]

                    echo "staging=${env.STAGING_URL} prod=${env.PROD_URL} registry=${env.ECR}"
                }
            }
        }
        stage('Checkout') {
            steps {
                checkout scm
                sh 'rm -rf reports && mkdir -p reports/coverage-html reports/e2e-html-report'
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

        stage('Test Backend') {
            steps {
                sh "docker build -f docker/api.Dockerfile --target test -t rmit-api:test-${env.SHA} ."
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
                        -e PYTHONPATH=".:app/server" \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} \
                        pytest tests/backend/ -c tests/backend/pytest.ini -m "unit or integration" \
                        --junitxml=/repo/reports/junit-backend.xml
                """
            }
            post {
                always {
                    sh """
                        docker rm -f ci-db-${env.BUILD_NUMBER} || true
                        docker network rm ci-${env.BUILD_NUMBER} || true
                    """
                    junit allowEmptyResults: false, testResults: 'reports/junit-backend.xml'
                }
            }
        }

        // Frontend unit tests (Vitest + jsdom) in the client image's test stage.
        // A failure here stops the pipeline before any push or deploy.
        stage('Test Frontend') {
            steps {
                sh "docker build -f docker/client.Dockerfile --target test -t rmit-client:test-${env.SHA} ."
                sh """
                    docker run --rm \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-client:test-${env.SHA} \
                        npx vitest run --config tests/frontend/vite.config.mjs --reporter=junit --outputFile=/repo/reports/junit-frontend.xml
                """
            }
            post {
                always {
                    junit allowEmptyResults: false, testResults: 'reports/junit-frontend.xml'
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
                sh """
                    scp -o StrictHostKeyChecking=no docker-compose.prod.yml ${STAGING}:~/deploy/
                    scp -o StrictHostKeyChecking=no docker/client-nginx-compose.conf ${STAGING}:~/deploy/docker/

                    ssh -o StrictHostKeyChecking=no ${STAGING} \
                      'cd ~/deploy \
                       && export ECR=${env.ECR} IMAGE_TAG=${env.SHA} \
                       && docker compose --env-file compose.env -f docker-compose.prod.yml pull \
                       && docker compose --env-file compose.env -f docker-compose.prod.yml up -d --remove-orphans \
                       && docker compose --env-file compose.env -f docker-compose.prod.yml \
                            run --rm --no-deps api python manage.py create_admin \
                       && docker compose --env-file compose.env -f docker-compose.prod.yml \
                            run --rm --no-deps api python manage.py seed_demo --demo-users \
                       && docker image prune -f'
                """
                // Printed so a rollback by hand needs no lookup: ssh in, cd ~/deploy,
                // and rerun the same two exports with an older IMAGE_TAG.
                echo "Deployed ${env.SHA} to ${env.STAGING_URL} from ${env.ECR}"
            }
        }

        stage('Smoke staging') {
            steps {
                sh """
                    docker run --rm --network host \
                        -e TARGET_URL=${STAGING_URL} \
                        -e BASE_URL=${STAGING_URL} \
                        -e GIT_SHA=${env.SHA} \
                        -e EXPECT_CATALOGUE=1 \
                        -e PYTHONPATH=".:app/server" \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} pytest tests/smoke/test_smoke.py -m smoke \
                        --junitxml=/repo/reports/junit-smoke-staging.xml
                """
            }
            post {
                always {
                    junit allowEmptyResults: false, testResults: 'reports/junit-smoke-staging.xml'
                }
            }
        }

        stage('E2E staging') {
            steps {
                sh "rm -rf test-results"
                sh """
                    docker run --rm --network host \
                        -e TARGET_URL=${STAGING_URL} \
                        -e CI=1 \
                        -v "\$PWD:/work" -w /work \
                        mcr.microsoft.com/playwright:v1.63.0-jammy \
                        sh -c "npm install -D @playwright/test axios && npx playwright test --config=tests/e2e/playwright.config.mjs; STATUS=\\\$?; chmod -R 777 reports test-results 2>/dev/null || true; exit \\\$STATUS"
                """
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit-e2e.xml'
                    archiveArtifacts artifacts: 'reports/e2e-html-report/**', allowEmptyArchive: true
                }
            }
        }

        stage('Migrate and seed prod') {
            steps {

                sh """
                    ssh -o StrictHostKeyChecking=no ${SWARM_MGR} '
                        set -e
                        docker service rm rmit-migrate 2>/dev/null || true

                        docker service create --name rmit-migrate --detach \
                            --restart-condition none \
                            --secret SECRET_KEY \
                            --secret DATABASE_URL \
                            --secret DJANGO_SUPERUSER_PASSWORD \
                            --env DJANGO_SETTINGS_MODULE=config.settings.prod \
                            --env ALLOWED_HOSTS=127.0.0.1 \
                            --env DJANGO_SUPERUSER_EMAIL=admin@rmit.edu.au \
                            --env USE_S3=True \
                            --env AWS_STORAGE_BUCKET_NAME=${env.MEDIA_BUCKET} \
                            --env AWS_S3_REGION_NAME=${env.AWS_REGION} \
                            --with-registry-auth \
                            ${ECR}/rmit-api:${env.SHA} \
                            sh -c "python manage.py migrate --noinput && python manage.py create_admin && python manage.py seed_demo"

                        for i in \$(seq 1 120); do
                            STATE=\$(docker service ps rmit-migrate --format '{{.CurrentState}}' | head -n1)
                            case "\$STATE" in
                                Complete*) echo "Migration complete"; break;;
                                Failed*|Rejected*)
                                    docker service logs rmit-migrate
                                    docker service rm rmit-migrate
                                    exit 1 ;;
                            esac
                            sleep 5
                        done

                        docker service logs rmit-migrate
                        docker service rm rmit-migrate
                    '
                """
            }
        }

        stage('Deploy prod (Swarm)') {
            steps {
                sh """
                    ssh -o StrictHostKeyChecking=no ${SWARM_MGR} 'mkdir -p ~/deploy/swarm ~/deploy/docker'
                    scp -o StrictHostKeyChecking=no swarm/stack.yml ${SWARM_MGR}:~/deploy/swarm/
                    scp -o StrictHostKeyChecking=no docker/client-nginx-compose.conf ${SWARM_MGR}:~/deploy/docker/

                    ssh -o StrictHostKeyChecking=no ${SWARM_MGR} '
                        cd ~/deploy &&
                        ECR=${ECR} GIT_SHA=${env.SHA} \
                        ALB_DNS=${env.ALB_DNS} MEDIA_BUCKET=${env.MEDIA_BUCKET} \
                        AWS_REGION=${env.AWS_REGION} EMAIL_ADDRESS=${env.EMAIL_ADDRESS} \
                        docker stack deploy \
                            -c swarm/stack.yml --with-registry-auth rmit
                    '
                """

                sh """
                    HITS=0
                    for i in \$(seq 1 80); do
                        BODY=\$(curl -s --max-time 5 ${PROD_URL}/api/version/ || true)
                        case "\$BODY" in
                            *${env.SHA}*) HITS=\$((HITS + 1)) ;;
                            *)            HITS=0 ;;
                        esac
                        if [ "\$HITS" -ge 10 ]; then
                            echo "The last 10 responses all report ${env.SHA}"
                            exit 0
                        fi
                        sleep 3
                    done
                    echo "The load balancer never settled on ${env.SHA}. Last response: \$BODY"
                    exit 1
                """
            }
        }

        stage('Smoke prod') {
            steps {
                sh """
                    docker run --rm --network host \
                        -e TARGET_URL=${PROD_URL} \
                        -e BASE_URL=${PROD_URL} \
                        -e GIT_SHA=${env.SHA} \
                        -e PYTHONPATH=".:app/server" \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} pytest tests/smoke/test_smoke.py -m smoke \
                        --junitxml=/repo/reports/junit-smoke-prod.xml
                """
            }
            post {
                always {
                    junit allowEmptyResults: false, testResults: 'reports/junit-smoke-prod.xml'
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