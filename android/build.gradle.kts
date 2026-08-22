allprojects {
    repositories {
        // 阿里云镜像优先（国内网络访问 google()/mavenCentral() 不稳定）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
// 本机只装了 build-tools 36.1.0；强制所有 Android 模块（含 mobile_scanner 等插件）
// 都用它，避免它们各自 pin 的 36.0.0 触发 sdkmanager 自动下载而挂起
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            buildToolsVersion = "36.1.0"
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension> {
            buildToolsVersion = "36.1.0"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
