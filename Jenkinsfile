pipeline {
  agent any

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
        echo 'Expecting Burp HTML report at burp/index.html'
        sh 'mkdir -p burp'
        sh 'test -f burp/index.html'
        sh 'echo "Burp report found"'
        sh 'ls -la burp || true'
      }
    }

    // Future stage placeholder for Test
    // Future stage placeholder for Deploy
  }

  post {
    always {
      publishHTML([
        reportDir: 'burp',
        reportFiles: 'index.html',
        reportName: 'Burp Security Report',
        keepAll: true,
        alwaysLinkToLastBuild: true,
        allowMissing: false
      ])
    }
  }
}
