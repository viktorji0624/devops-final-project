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
        echo 'Expecting Burp HTML report at burpsuite/report/index.html'
        sh 'mkdir -p burpsuite/report'
        sh 'test -f burpsuite/report/index.html'
        sh 'echo "Burp report found"'
        sh 'ls -la burpsuite/report || true'
      }
    }

    // Future stage placeholder for Test
    // Future stage placeholder for Deploy
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
