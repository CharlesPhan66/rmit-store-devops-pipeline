pipeline {
    agent any

    environment {
        API_IMAGE        = 'rmit-store-api'
        FRONTEND_IMAGE   = 'rmit-store-frontend'
        TEST_DB_CONTAINER = 'jenkins-test-db'
        TEST_DB_PORT     = '5433'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build API image') {
            steps {
                dir('app/server') {
                    sh "docker build -t ${API_IMAGE}:${env.BUILD_NUMBER} ."
                }
            }
        }

        stage('Build Frontend image') {
            steps {
                dir('app/client') {
                    sh "docker build -t ${FRONTEND_IMAGE}:${env.BUILD_NUMBER} ."
                }
            }
        }

        stage('Backend tests') {
            steps {
                sh """
                    docker rm -f ${TEST_DB_CONTAINER} || true

                    docker run -d --name ${TEST_DB_CONTAINER} \\
                        -e POSTGRES_USER=rmit \\
                        -e POSTGRES_PASSWORD=rmit \\
                        -e POSTGRES_DB=rmit_store \\
                        -p ${TEST_DB_PORT}:5432 postgres:16

                    echo 'Waiting for test database to accept connections...'
                    for i in \$(seq 1 15); do
                        docker exec ${TEST_DB_CONTAINER} pg_isready -U rmit && break
                        sleep 2
                    done

                    mkdir -p test-reports

                    docker run --rm --network host \\
                        -e DATABASE_URL=postgres://rmit:rmit@localhost:${TEST_DB_PORT}/rmit_store \\
                        -e SECRET_KEY=jenkins-test-key \\
                        -e ALLOWED_HOSTS=localhost,127.0.0.1 \\
                        -e DJANGO_SETTINGS_MODULE=config.settings.dev \\
                        -v "\$(pwd)/test-reports:/app/test-reports" \\
                        --entrypoint sh ${API_IMAGE}:${env.BUILD_NUMBER} \\
                        -c "pip install --quiet unittest-xml-reporting && \\
                            python manage.py test \\
                                --testrunner=xmlrunner.extra.djangotestrunner.XMLTestRunner \\
                                --output-dir=/app/test-reports \\
                                apps.orders apps.catalog apps.core"
                """
            }
            post {
                always {
                    sh "docker rm -f ${TEST_DB_CONTAINER} || true"
                    junit 'test-reports/*.xml'
                }
            }
        }

        stage('Frontend E2E tests') {
            steps {
                echo 'TODO: Playwright browser binaries not yet installed on the Jenkins host (blocked by disk space during setup). See PR description for the plan.'
            }
        }

        stage('Deploy to staging') {
            steps {
                echo 'TODO: blocked on G1 (Infrastructure as Code) - no staging environment exists yet. See PR description.'
            }
        }

        stage('Promote to production') {
            when {
                branch 'main'
            }
            steps {
                echo 'TODO: blocked on G1 - no production environment exists yet. See PR description.'
            }
        }
    }

    post {
        failure {
            emailext (
                subject: "FAILED: Jenkins Pipeline - ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Build failed. Check console output at ${env.BUILD_URL}",
                to: 'team-email@example.com'
            )
        }
    }
}