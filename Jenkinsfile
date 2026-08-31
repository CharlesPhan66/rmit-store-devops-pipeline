// Webhook trigger verification
pipeline {
    agent any

    environment {
        API_IMAGE          = 'rmit-store-api'
        FRONTEND_IMAGE     = 'rmit-store-frontend'
        TEST_DB_CONTAINER  = 'jenkins-test-db'
        TEST_DB_PORT       = '5433'
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
                        -e DJANGO_SETTINGS_MODULE=ci_test_settings \\
                        -v "\$(pwd)/test-reports:/app/test-reports" \\
                        --entrypoint sh ${API_IMAGE}:${env.BUILD_NUMBER} \\
                        -c "pip install --quiet unittest-xml-reporting && python manage.py test apps.orders apps.catalog apps.core"
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
        sh """
            docker rm -f e2e-api e2e-frontend || true

            docker run -d --name e2e-api --network host \\
                -e DATABASE_URL=postgres://rmit:rmit@localhost:${TEST_DB_PORT}/rmit_store \\
                -e SECRET_KEY=jenkins-e2e-key \\
                -e ALLOWED_HOSTS=localhost,127.0.0.1 \\
                -e DJANGO_SETTINGS_MODULE=config.settings.dev \\
                ${API_IMAGE}:${env.BUILD_NUMBER}

            echo 'Waiting for API to become healthy...'
            for i in \$(seq 1 15); do
                curl -sf http://localhost:8000/healthz/ && break
                sleep 2
            done

            docker exec e2e-api python manage.py seed_demo \\
                --admin-email admin@rmit.edu.au \\
                --admin-password 'RmitStore2767!' --no-images || true

            echo "window.__APP_CONFIG__ = { API_BASE_URL: 'http://localhost:8000/api' }" > /tmp/e2e-config.js

            docker run -d --name e2e-frontend --network host \\
                -v /tmp/e2e-config.js:/usr/share/nginx/html/config.js:ro \\
                ${FRONTEND_IMAGE}:${env.BUILD_NUMBER}

            echo 'Waiting for frontend to respond...'
            for i in \$(seq 1 15); do
                curl -sf http://localhost:80/ && break
                sleep 2
            done

            docker run --rm --network host \\
                -v "\$(pwd)/app/client:/work" -w /work \\
                mcr.microsoft.com/playwright:v1.62.1-jammy \\
                sh -c "npm install --no-save @playwright/test && npx playwright test --config=playwright.config.js"
        """
    }
    post {
        always {
            sh "docker rm -f e2e-api e2e-frontend jenkins-test-db || true"
        }
    }
}

        stage('Deploy to staging') {
            steps {
                echo 'TODO: blocked on G1 (Infrastructure as Code) - no staging environment exists yet.'
            }
        }

        stage('Promote to production') {
            when {
                branch 'main'
            }
            steps {
                echo 'TODO: blocked on G1 - no production environment exists yet.'
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