allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
// Use traditional File-based buildDir assignment to avoid issues with the layout API
val newBuildDirFile = rootProject.rootDir.resolve("../build").normalize()
rootProject.buildDir = newBuildDirFile

subprojects {
    val newSubprojectBuildDirFile = newBuildDirFile.resolve(project.name)
    project.buildDir = newSubprojectBuildDirFile
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
