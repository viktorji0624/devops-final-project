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

    // Future stage placeholder: Test
    // Future stage placeholder: SonarQube Analysis
    // Future stage placeholder: Deploy
  }
}
