# Docker ve Konteyner Teknolojileri - 05 Raporu

**Proje:** Jenkins ile GitOps Pipeline, Swarm CD ve Siege ile Kesintisiz Deployment Testi

---

## 1. Jenkins-Server — IP ve Durum Detayları

| Özellik | Değer |
|---|---|
| **IP / URL** | `http://43.229.94.189:8080` |
| **İşletim Sistemi** | Ubuntu 24.04.2 LTS |
| **Donanım** | 2 vCPU / 3.8 GB RAM |
| **Jenkins Servisi** | `active (running)` |
| **Docker** | v29.7.2 |
| **Uptime** | 23 saat 33 dk |
| **Yapılandırma** | SCM Polling (`H/2 * * * *`) — her push otomatik build |
| **Job Adı** | `django-pipeline` |

**Jenkins kurulum detayları:**
- Docker soket yetkisi: `sudo usermod -aG docker jenkins` + `sudo systemctl restart jenkins`
- Docker Hub kimlik bilgileri: `docker-hub-credentials` (Username with password)
- Swarm Manager SSH anahtarı: `swarm-manager-key` credential'ı
- SSH Agent plugin kuruldu

---

## 2. Jenkinsfile (başarıyla koşan pipeline)

```groovy
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
                echo "Build Docker image: v1.0.${BUILD_NUMBER} ve latest"
                sh "docker build -t ${DOCKER_IMAGE}:v1.0.${BUILD_NUMBER} -t ${DOCKER_IMAGE}:latest ."
            }
        }

        stage('Push Image') {
            steps {
                echo "Pushing image to Docker Hub..."
                withCredentials([usernamePassword(credentialsId: 'docker-hub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                    sh "docker push ${DOCKER_IMAGE}:v1.0.${BUILD_NUMBER}"
                    sh "docker push ${DOCKER_IMAGE}:latest"
                }
            }
        }

        stage('Deploy to Swarm') {
            steps {
                echo "Zero-Downtime Deploy starting..."
                sshagent(['swarm-manager-key']) {
                    sh "scp -o StrictHostKeyChecking=no docker-stack.yml nginx.conf ${MANAGER_USER}@${MANAGER_IP}:/home/${MANAGER_USER}/"
                    sh "ssh -o StrictHostKeyChecking=no ${MANAGER_USER}@${MANAGER_IP} 'docker stack deploy -c /home/${MANAGER_USER}/docker-stack.yml my-django-stack'"
                }
            }
        }

        stage('Siege Test') {
            steps {
                echo "Zero-Downtime siege test starting..."
                sh "siege -c 10 -t 30s http://${MANAGER_IP}/"
            }
        }
    }
}
```

---

## 3. docker-stack.yml (healthcheck + update_config ekli)

```yaml
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: django_db
      POSTGRES_USER: django_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    networks:
      - django-overlay
    volumes:
      - pgdata:/var/lib/postgresql/data
    deploy:
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

  web:
    image: azizmevlana/complex-multistage-app:latest
    environment:
      - DJANGO_SETTINGS_MODULE=django_project.settings
      - DB_NAME=django_db
      - DB_USER=django_user
      - DB_HOST=db
    secrets:
      - django_secret_key_v2
      - db_password
    networks:
      - django-overlay
    volumes:
      - static_volume:/app/staticfiles
    healthcheck:
      test: ["CMD-SHELL", "python -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:8000/health\")' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    networks:
      - django-overlay
    depends_on:
      - web
    configs:
      - source: nginx_config_v2
        target: /etc/nginx/conf.d/default.conf
    volumes:
      - static_volume:/app/staticfiles:ro
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure

networks:
  django-overlay:
    external: true

volumes:
  static_volume:
  pgdata:

secrets:
  db_password:
    external: true
  django_secret_key_v2:
    external: true

configs:
  nginx_config_v2:
    file: ./nginx.conf
```

### update_config ve healthcheck açıklamaları

**`order: start-first`:** Yeni container'lar sağlıklı şekilde ayağa kalkana kadar eski container'lar çalışmaya devam eder. Yeni container hazır olduktan sonra eski kapatılır → **sıfır kesinti**. Varsayılan `rolling`'de önce eski durdurulur, bu da kesintiye neden olabilir.

**`parallelism: 1`:** Aynı anda yalnızca 1 replica güncellenir. `delay: 10s` ile her birim güncelleme sonrası 10 sn beklenir. Böylece güncelleme kontrollü ve adım adım ilerler.

**`failure_action: rollback`:** Güncelleme başarısız olursa (healthcheck kırmızı) Swarm otomatik olarak önceki sürüme geri döner.

**Healthcheck:** Her 10 saniyede bir `http://localhost:8000/health` endpoint'ine istek atar (Django tarafında tanımlı, DB bağlantısını da kontrol eder). 5 sn timeout, 3 retries; ilk 15 sn `start_period` ile başlangıç süresi tolere edilir. Sağlıklı olmayan container `failure_action: rollback` ile devre dışı bırakılır.

---

## 4. Jenkins Pipeline Ekran Görüntüsü

`http://43.229.94.189:8080/job/django-pipeline/6/` adresinde **Build #6**:

- Checkout ✓
- Build Image ✓
- Push Image ✓
- Deploy to Swarm ✓
- Siege Test ✓
- **Sonuç: SUCCESS**

---

## 5. ⭐ Siege Test Raporu (canlı deployment sırasında)

**Komut:** `siege -c 10 -t 30s http://43.229.92.13/`

```
{	"transactions":			       11371,
	"availability":			      100.00,      ← ✅ SIFIR KESİNTİ (%100)
	"elapsed_time":			       29.82,
	"data_transferred":		      101.87,
	"response_time":		        0.03,
	"transaction_rate":		      381.32,
	"throughput":			        3.42,
	"concurrency":			        9.95,
	"successful_transactions":	        9707,
	"failed_transactions":		           0,   ← ✅ HATA = 0
	"longest_transaction":		        0.23,
	"shortest_transaction":		        0.00
}
```

**Sonuç:** Deployment (start-first rolling update) sırasında 11,371 istek gönderildi. **Availability: %100.00**, **0 başarısız istek** → kullanıcılar güncelleme anında hiçbir kesinti yaşamadı.

**Swarm doğrulaması:** Build #6 sonrası yeni imaj (`sha256:39482e...`) `start-first` ile tüm replica'lara rollout edildi, eski imajlar sırayla kapatıldı ve `/health` endpoint'i 200 döndü.
