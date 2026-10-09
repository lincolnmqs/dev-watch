import Foundation

struct ServiceIdentifier {
    struct ProjectContext {
        let packageName: String?
        let scripts: [String: String]
        let dependencyNames: Set<String>
    }

    struct ServiceInfo {
        let name: String
    }

    static func identify(
        processName: String,
        executablePath: String?,
        commandLine: [String]?,
        port: Int?,
        projectContext: ProjectContext?
    ) -> ServiceInfo? {
        let exec = (executablePath as NSString?)?.lastPathComponent ?? processName
        let args = (commandLine ?? []).joined(separator: " ").lowercased()
        let projectInfo = identifyFromProjectContext(projectContext)

        if let projectInfo {
            return projectInfo
        }

        if let port {
            switch port {
            case 3000, 3001, 5173, 8080:
                if exec.lowercased() == "node" || exec.lowercased() == "bun" {
                    return .init(name: "Node")
                }
            case 5432:
                return .init(name: "PostgreSQL")
            case 6379:
                return .init(name: "Redis")
            default:
                break
            }
        }

        switch exec.lowercased() {
        case "node":
            if args.contains("next") || args.contains("next-server") { return .init(name: "Next.js") }
            if args.contains("vite") { return .init(name: "Vite") }
            if args.contains("nuxt") { return .init(name: "Nuxt") }
            if args.contains("@nestjs") || args.contains("nest") { return .init(name: "NestJS") }
            if args.contains("react-scripts") { return .init(name: "React Scripts") }
            if args.contains("expo") { return .init(name: "Expo") }
            if args.contains("gatsby") { return .init(name: "Gatsby") }
            if args.contains("strapi") { return .init(name: "Strapi") }
            if args.contains("remix") { return .init(name: "Remix") }
            if args.contains("astro") { return .init(name: "Astro") }
            if args.contains("sveltekit") || args.contains("svelte-kit") { return .init(name: "SvelteKit") }
            if args.contains("webpack") { return .init(name: "Webpack") }
            if args.contains("express") { return .init(name: "Express") }
            if args.contains("fastify") { return .init(name: "Fastify") }
            if args.contains("hapi") { return .init(name: "Hapi") }
            return .init(name: "Node")
        case "bun":
            if args.contains("next") { return .init(name: "Next.js") }
            return .init(name: "Bun")
        case "deno":
            return .init(name: "Deno")
        case "python", "python3", "python3.9", "python3.10", "python3.11", "python3.12", "python3.13":
            if args.contains("uvicorn") { return .init(name: "FastAPI") }
            if args.contains("gunicorn") { return .init(name: "Gunicorn") }
            if args.contains("manage.py") || args.contains("django") { return .init(name: "Django") }
            if args.contains("flask") { return .init(name: "Flask") }
            if args.contains("streamlit") { return .init(name: "Streamlit") }
            if args.contains("tornado") { return .init(name: "Tornado") }
            if args.contains("aiohttp") { return .init(name: "aiohttp") }
            return .init(name: "Python")
        case "ruby":
            if args.contains("rails") { return .init(name: "Rails") }
            if args.contains("sinatra") { return .init(name: "Sinatra") }
            if args.contains("puma") { return .init(name: "Puma") }
            return .init(name: "Ruby")
        case "rails":
            return .init(name: "Rails")
        case "puma":
            return .init(name: "Puma")
        case "postgres", "postgresql":
            return .init(name: "PostgreSQL")
        case "redis-server":
            return .init(name: "Redis")
        case "mongod":
            return .init(name: "MongoDB")
        case "mysqld", "mysql":
            return .init(name: "MySQL")
        case "mariadbd":
            return .init(name: "MariaDB")
        case "nginx":
            return .init(name: "Nginx")
        case "caddy":
            return .init(name: "Caddy")
        case "httpd":
            return .init(name: "Apache")
        case "traefik":
            return .init(name: "Traefik")
        case "java":
            if args.contains("spring") { return .init(name: "Spring Boot") }
            if args.contains("quarkus") { return .init(name: "Quarkus") }
            if args.contains("micronaut") { return .init(name: "Micronaut") }
            return .init(name: "Java")
        case "dotnet":
            return .init(name: ".NET")
        case "go":
            return .init(name: "Go")
        case "php", "php-fpm":
            if args.contains("artisan") { return .init(name: "Laravel") }
            return .init(name: "PHP")
        case "cargo":
            return .init(name: "Rust")
        case "elixir", "beam.smp":
            if args.contains("phoenix") { return .init(name: "Phoenix") }
            return .init(name: "Elixir")
        case "docker-proxy":
            return .init(name: "Docker")
        default:
            return nil
        }
    }

    private static func identifyFromProjectContext(_ context: ProjectContext?) -> ServiceInfo? {
        guard let context else { return nil }

        let deps = context.dependencyNames
        let scripts = context.scripts.values.joined(separator: " ").lowercased()
        let packageName = context.packageName?.lowercased() ?? ""

        if deps.contains("@nestjs/core") || deps.contains("@nestjs/common") || scripts.contains("nest start") || scripts.contains("nest build") {
            return .init(name: "NestJS")
        }

        if deps.contains("vite") || deps.contains("@vitejs/plugin-react") || scripts.contains("vite") {
            return .init(name: "Vite")
        }

        if deps.contains("next") || scripts.contains("next dev") || scripts.contains("next start") {
            return .init(name: "Next.js")
        }

        if deps.contains("@angular/core") || packageName.contains("angular") {
            return .init(name: "Angular")
        }

        if deps.contains("react") || deps.contains("react-dom") || packageName.contains("frontend") || packageName.contains("web") {
            return .init(name: "React")
        }

        if deps.contains("webpack") || scripts.contains("webpack") {
            return .init(name: "Webpack")
        }

        if deps.contains("express") || deps.contains("fastify") || deps.contains("hapi") {
            return .init(name: "Node")
        }

        if packageName.hasPrefix("ms-") || packageName.contains("api") || packageName.contains("backend") || packageName.contains("service") {
            return .init(name: "Node")
        }

        return nil
    }
}
