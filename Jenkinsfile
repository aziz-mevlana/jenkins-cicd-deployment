pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'azizmevlana/complex-multistage-app'
        MANAGER_IP = '43.229.92.13' 
        MANAGER_USER = 'ubuntu'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Image') {
            steps {
                echo "🚀 İmaj build ediliyor: v1.0.${BUILD_NUMBER} ve latest"
                sh "docker build -t ${DOCKER_IMAGE}:v1.0.${BUILD_NUMBER} -t ${DOCKER_IMAGE}:latest ."
            }
        }

        stage('Push Image') {
            steps {
                echo "📦 İmaj Docker Hub'a gönderiliyor..."
                withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                    sh "docker push ${DOCKER_IMAGE}:v1.0.${BUILD_NUMBER}"
                    sh "docker push ${DOCKER_IMAGE}:latest"
                }
            }
        }

        stage('Deploy to Swarm') {
            steps {
                echo "🌐 Swarm kümesine Zero-Downtime Deploy başlatılıyor..."
                
                // Hem docker-stack.yml hem de nginx.conf dosyaları Manager sunucusuna kopyalanır
                sh "scp -i ~/.ssh/key_devops -o StrictHostKeyChecking=no docker-stack.yml nginx.conf ${MANAGER_USER}@${MANAGER_IP}:/home/${MANAGER_USER}/"
                
                // Manager sunucusunda deploy komutu çalıştırılır
                sh "ssh -i ~/.ssh/key_devops -o StrictHostKeyChecking=no ${MANAGER_USER}@${MANAGER_IP} 'docker stack deploy -c /home/${MANAGER_USER}/docker-stack.yml my-django-stack'"
            }
        }
    }
}