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
          sh './mvnw sonar:sonar -Dsonar.projectKey=spring-petclinic -Dsonar.projectName=spring-petclinic'
        }
      }
    }

    // Future stage placeholder: Test
    // Future stage placeholder: Deploy
  }
}
