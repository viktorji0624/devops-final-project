pipeline {
  agent any

  triggers {
    pollSCM('H/5 * * * *') // SCM polling every 5 minutes
  }

  stages {
    stage('Checkout') {
      steps {
        // Pipeline script is loaded from SCM; this ensures workspace source is present.
        checkout scm
      }
    }

    stage('Build') {
      steps {
        sh './mvnw clean package -DskipTests'
      }
    }

    stage('SonarQube Analysis') {
      steps {
        withSonarQubeEnv('sonarqube') {
          withCredentials([string(credentialsId: 'sonarqube-token-new', variable: 'SONAR_TOKEN')]) {
            sh './mvnw sonar:sonar -Dsonar.projectKey=spring-petclinic -Dsonar.projectName=spring-petclinic -Dsonar.login=$SONAR_TOKEN'
          }
        }
      }
    }

    stage('Security Scan') {
      steps {
        echo 'Expecting Burp HTML report at burpsuite/report/index.html'
        sh 'mkdir -p burpsuite/report'
        sh 'test -f burpsuite/report/index.html'
        sh 'echo "Burp report found"'
        sh 'ls -la burpsuite/report || true'
      }
    }

    stage('Deploy') {
      steps {
        script {
          def vagrantKey = sh(
            script: 'find /vagrant-keys/machines/default -name private_key -print -quit 2>/dev/null || true',
            returnStdout: true
          ).trim()

          if (!vagrantKey) {
            echo 'SKIP: Vagrant private key not found at /vagrant-keys/. VM may not be running.'
            echo 'To enable deployment, run: vagrant up && docker compose restart jenkins'
          } else if (sh(script: 'command -v ansible-playbook >/dev/null 2>&1', returnStatus: true) != 0) {
            echo 'SKIP: ansible-playbook not found on this Jenkins agent.'
            echo 'Rebuild the Jenkins image: docker compose build --no-cache jenkins && docker compose up -d --force-recreate jenkins'
          } else {
            sh """
              ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                --private-key '${vagrantKey}' \
                -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
            """
          }
        }
      }
    }
  }

  post {
    always {
      publishHTML([
        reportDir: 'burpsuite/report',
        reportFiles: 'index.html',
        reportName: 'Burp Security Report',
        keepAll: true,
        alwaysLinkToLastBuild: true,
        allowMissing: false
      ])
    }
  }
}
