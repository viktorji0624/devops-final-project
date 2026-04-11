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

    stage('Test') {
      steps {
        sh './mvnw test'
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

    stage('Deploy') {
      steps {
        sh '''
          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
            --private-key .vagrant/machines/default/vmware_desktop/private_key \
            -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
        '''
      }
    }

    stage('Burp Suite Scan') {
      steps {
        echo 'TODO: Burp Suite scan integration - requires API access and scripting to automate scans against the deployed application.'
      }
    }
  }

  post {
    always {
      junit '**/target/surefire-reports/*.xml'
    }
  }
}
