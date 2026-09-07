// Author: @CharlesPhan66 (Charles Phan)
// Last updated: 2/9/2026
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
                    env.PROD_URL    = "http://" + ssm('/rmit/prod/ALB_DNS')

                    env.AWS_REGION  = env.ECR.split('\\.')[3]

                    echo "staging=${env.STAGING_URL} prod=${env.PROD_URL} registry=${env.ECR}"
                }
            }
        }
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

        // Pushes to Amazon ECR. Note what is absent: no withCredentials, no static
        // token. `aws` gets a 12-hour token from this instance's profile, which is
        // the reason for using ECR over Docker Hub - every other part of this
        // project already dropped its static keys.
        //
        // Requires on the Jenkins host: the aws CLI, and an instance profile with
        // ECR permissions (LabInstanceProfile on Learner Lab).
        //
        // The Docker Hub equivalent, if you ever switch back, needs the static
        // token restored:
        //   withCredentials([usernamePassword(credentialsId: 'dockerhub',
        //         usernameVariable: 'U', passwordVariable: 'P')]) {
        //     sh 'echo "$P" | docker login -u "$U" --password-stdin'
        //   }
        // Whichever you pick, ${ECR} must match it - the three image: lines in
        // docker-compose.prod.yml and swarm/stack.yml all read that one variable.
        // REPLACE: prefix ${ECR} with ${DOCKER_NS} that you filled in above if you prefer Docker Hub (PM prefers ECR ^^)
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

        // The app staging host holds no checkout and no GitHub credential. Compose reads
        // exactly two files from disk, and both are copied here from this
        // workspace, which is already standing at ${env.SHA}. compose.env sits
        // in ~/deploy already, written by Ansible from SSM, and is never
        // overwritten, Jenkins therefore handles no secret at all.
        //
        // No docker login: the docker role installed amazon-ecr-credential-helper,
        // so pull authenticates from the instance profile every time.
        // Still follow the structure after copying the files
        // NOTE: BY THIS, WE DO NOT NEED DEPLOY.SH ANYMORE, WE CAN JUST USE JENKINSFILE TO DEPLOY STAGING AND PROD
        stage('Deploy Staging') {
            steps {
                sshagent(['app-host-key']) {
                    sh """
                        scp -o StrictHostKeyChecking=no docker-compose.prod.yml ${STAGING}:~/deploy/
                        scp -o StrictHostKeyChecking=no docker/client-nginx-compose.conf ${STAGING}:~/deploy/docker/

                        ssh -o StrictHostKeyChecking=no ${STAGING} \
                          'cd ~/deploy \
                           && export ECR=${env.ECR} IMAGE_TAG=${env.SHA} \
                           && docker compose --env-file compose.env -f docker-compose.prod.yml pull \
                           && docker compose --env-file compose.env -f docker-compose.prod.yml up -d --remove-orphans \
                           && docker image prune -f'
                    """
                }
                // Printed so a rollback by hand needs no lookup: ssh in, cd ~/deploy,
                // and rerun the same two exports with an older IMAGE_TAG.
                echo "Deployed ${env.SHA} to ${env.STAGING_URL} from ${env.ECR}"
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

        stage('Migrate prod') {
            when {
                anyOf {
                    branch 'main'
                    branch 'charles/self-work'
                }
            }
            steps {
                sshagent(['app-host-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${SWARM_MGR} '
                            set -e
                            docker service rm rmit-migrate 2>/dev/null || true

                            docker service create --name rmit-migrate --detach \
                                --restart-condition none \
                                --secret SECRET_KEY \
                                --secret DATABASE_URL \
                                --env DJANGO_SETTINGS_MODULE=config.settings.prod \
                                --env ALLOWED_HOSTS=127.0.0.1 \
                                --with-registry-auth \
                                ${ECR}/rmit-api:${env.SHA} python manage.py migrate --noinput

                            for i in \$(seq 1 60); do
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
        }

        stage('Deploy prod (Swarm)') {
            when {
                anyOf {
                    branch 'main'
                    branch 'charles/self-work'
                }
            }
            steps {
                sshagent(['app-host-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${SWARM_MGR} 'mkdir -p ~/deploy/swarm ~/deploy/docker'
                        scp -o StrictHostKeyChecking=no swarm/stack.yml ${SWARM_MGR}:~/deploy/swarm/
                        scp -o StrictHostKeyChecking=no docker/client-nginx-compose.conf ${SWARM_MGR}:~/deploy/docker/

                        ssh -o StrictHostKeyChecking=no ${SWARM_MGR} '
                            cd ~/deploy &&
                            ECR=${ECR} GIT_SHA=${env.SHA} docker stack deploy \
                                -c swarm/stack.yml --with-registry-auth rmit
                        '
                    """
                }
            }
        }

        stage('Smoke prod') {
            when {
                anyOf {
                    branch 'main'
                    branch 'charles/self-work'
                }
            }
            steps {
                sh """
                    docker run --rm --network host \
                        -e BASE_URL=${PROD_URL} \
                        -e GIT_SHA=${env.SHA} \
                        -v "\$PWD/reports:/repo/reports" \
                        rmit-api:test-${env.SHA} pytest tests/smoke --junitxml=reports/smoke-prod.xml
                """
            }
            post {
                always {
                    junit 'reports/smoke-prod.xml'
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