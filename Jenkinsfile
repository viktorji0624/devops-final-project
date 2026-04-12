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

    stage('Burp Suite Scan') {
      steps {
        echo 'TODO: Burp Suite scan integration - requires API access and scripting to automate scans against the deployed application.'
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          if ! command -v ansible-playbook >/dev/null 2>&1; then
            echo "ERROR: ansible-playbook not found on this Jenkins agent."
            echo "PATH=$PATH"
            echo "If Jenkins runs in Docker, rebuild/recreate the jenkins service so jenkins/Dockerfile is applied:"
            echo "docker compose build --no-cache jenkins && docker compose up -d --force-recreate jenkins"
            exit 127
          fi

          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
            --private-key .vagrant/machines/default/vmware_desktop/private_key \
            -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
        '''
      }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
    }
  }
}
