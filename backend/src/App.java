import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.Duration;
import java.util.List;
import com.sun.net.httpserver.*;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLEncoder;

public class App {
    private static final URI HEALTH_URI = URI.create("http://127.0.0.1:5000/health");
    private static final URI PROCESS_URI = URI.create("http://127.0.0.1:5000/process_input");
    private static final Path BACKEND_DIR = findBackendDirectory();
    private static final Path INPUT_FILE = BACKEND_DIR.resolve("ai_server.in");
    private static final Path OUTPUT_FILE = BACKEND_DIR.resolve("ai_server.out");
    private static final Path MEMORY_FILE = BACKEND_DIR.resolve("memory_counts.json");
    private static final Object PROCESS_LOCK = new Object();

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(8080), 0);
        server.createContext("/api/", new apiHandler());
        server.setExecutor(null);
        server.start();
    }

    static class apiHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String path = exchange.getRequestURI().getPath();
            String method = exchange.getRequestMethod();

            if( method.equals("GET") && path.equals("/api/progress/history")){
                getProgressHistory(exchange);
                return;
            }
            if (method.equals("OPTIONS")) {
                setCorsHeaders(exchange);
                exchange.sendResponseHeaders(204, -1);
                exchange.close();
                return;
            }
            if (method.equals("GET") && path.equals("/api/health")) {
                sendJson(exchange, 200, "{\"status\":\"ok\"}");
                return;
            }
            if (method.equals("POST") && path.equals("/api/ai/start")) {
                startAiServer(exchange);
                return;
            }
            if (method.equals("POST") && path.equals("/api/checkins/process")) {
                processCheckins(exchange);
                return;
            }
            if (method.equals("GET") && path.equals("/api/checkins/memory")) {
                readMemory(exchange);
                return;
            }
            if (method.equals("POST") && path.equals("/api/checkins/memory/update")) {
                updateMemory(exchange);
                return;
            }
            if (method.equals("GET") && path.equals("/api/checkins/support")) {
                showSupportPrompts(exchange);
                return;
            }
            sendJson(exchange, 404, "{\"error\":\"not_found\"}");
        }
    }

    private static void startAiServer(HttpExchange exchange) throws IOException {
        synchronized (PROCESS_LOCK) {
            try {
                boolean started = runAi_server();
                sendJson(exchange, 200, "{\"status\":\"" + (started ? "started" : "already_running") + "\"}");
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                sendError(exchange, 502, "Starting the AI server was interrupted.");
            } catch (IOException error) {
                sendError(exchange, 502, error.getMessage());
            }
        }
    }


    private static void processCheckins(HttpExchange exchange) throws IOException {
        String input = new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8).trim();
        String userId = exchange.getRequestHeaders().getFirst("X-User-ID");
        String timezoneOffsetHeader =
                exchange.getRequestHeaders().getFirst("X-Time-Zone-Offset-Minutes");

        if (input.isEmpty()) {
            sendJson(exchange, 400, "{\"error\":\"Check-in text is required.\"}");
            return;
        }
        if (userId == null || userId.isBlank()) {
            sendJson(exchange, 400, "{\"error\":\"X-User-ID header is required.\"}");
            return;
        }

        final int timezoneOffsetMinutes;
        try {
            timezoneOffsetMinutes = Integer.parseInt(timezoneOffsetHeader);
            if (timezoneOffsetMinutes < -14 * 60 || timezoneOffsetMinutes > 14 * 60) {
                throw new NumberFormatException("Timezone offset is out of range.");
            }
        } catch (NumberFormatException | NullPointerException error) {
            sendJson(exchange, 400, "{\"error\":\"A valid X-Time-Zone-Offset-Minutes header is required.\"}");
            return;
        }

        synchronized (PROCESS_LOCK) {
            try {
                runAi_server();
                Files.writeString(INPUT_FILE, input + System.lineSeparator(), StandardCharsets.UTF_8);
                promptServer(userId, Instant.now().toString(), timezoneOffsetMinutes);
                runMemoryManager();
                String response = Files.readString(OUTPUT_FILE, StandardCharsets.UTF_8);
                String supportGuidance = runSupportPrompts();
                int responseEnd = response.lastIndexOf('}');
                if (responseEnd < 0 || !response.substring(responseEnd + 1).isBlank()) {
                    throw new IOException("Check-in processor returned invalid JSON.");
                }
                response = response.substring(0, responseEnd)
                        + ",\"support_guidance\":\"" + jsonEscape(supportGuidance) + "\"}";
                sendJson(exchange, 200, response);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                sendError(exchange, 502, "Backend processing was interrupted.");
            } catch (IOException error) {
                sendError(exchange, 502, error.getMessage());
            }
        }
    }

    private static void readMemory(HttpExchange exchange) throws IOException {
        synchronized (PROCESS_LOCK) {
            try {
                if (!Files.exists(MEMORY_FILE)) {
                    Files.writeString(
                            MEMORY_FILE,
                            "{\"total_checkins\":0,\"dangerous_checkins\":0,"
                                    + "\"emotions\":{},\"tones\":{},"
                                    + "\"danger_levels\":{},\"danger_types\":{},"
                                    + "\"processed_entries\":{}}",
                            StandardCharsets.UTF_8
                    );
                }
                sendJson(exchange, 200, Files.readString(MEMORY_FILE, StandardCharsets.UTF_8));
            } catch (IOException error) {
                sendError(exchange, 500, "Could not read memory counts: " + error.getMessage());
            }
        }
    }

    private static void updateMemory(HttpExchange exchange) throws IOException {
        synchronized (PROCESS_LOCK) {
            try {
                runMemoryManager();
                sendJson(exchange, 200, Files.readString(MEMORY_FILE, StandardCharsets.UTF_8));
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                sendError(exchange, 500, "Memory update was interrupted.");
            } catch (IOException error) {
                sendError(exchange, 500, "Could not update memory: " + error.getMessage());
            }
        }
    }

    private static void showSupportPrompts(HttpExchange exchange) throws IOException {
        synchronized (PROCESS_LOCK) {
            try {
                String guidance = runSupportPrompts();
                sendJson(exchange, 200, "{\"guidance\":\"" + jsonEscape(guidance) + "\"}");
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                sendError(exchange, 500, "Support prompts were interrupted.");
            } catch (IOException error) {
                sendError(exchange, 500, "Could not load support prompts: " + error.getMessage());
            }
        }
    }

    private static void promptServer(String userId, String timestamp, int timezoneOffsetMinutes)
            throws IOException, InterruptedException {
        HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
        waitForServer(client);

        String metadata = "{\"user_id\":\"" + jsonEscape(userId)
                + "\",\"timestamp\":\"" + jsonEscape(timestamp)
                + "\",\"timezone_offset_minutes\":" + timezoneOffsetMinutes + "}";
        HttpRequest request = HttpRequest.newBuilder(PROCESS_URI)
                .timeout(Duration.ofSeconds(150))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(metadata, StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> response = client.send(request,HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));

        if (response.statusCode() != 200) {
            throw new IOException(
                "Python could not process the input (HTTP "+ response.statusCode() + "): " + response.body()
            );
        }
    }

    private static void waitForServer(HttpClient client) throws IOException, InterruptedException {
        waitForServer(client, null);
    }

    private static void waitForServer(HttpClient client, Process process)
            throws IOException, InterruptedException {
        long deadline = System.nanoTime() + Duration.ofSeconds(15).toNanos();
        IOException lerr = null;

        while (System.nanoTime() < deadline) {
            if (process != null && !process.isAlive()) {
                throw new IOException(
                        "ai_server.py exited with code " + process.exitValue()
                                + " before its health check succeeded."
                );
            }
            HttpRequest request = HttpRequest.newBuilder(HEALTH_URI).timeout(Duration.ofSeconds(2)).GET().build();
            try {
                HttpResponse<Void> response = client.send(request,HttpResponse.BodyHandlers.discarding());
                if (response.statusCode() == 200) {
                    return;
                }
                lerr = new IOException(
                        "Python health check returned HTTP " + response.statusCode()
                );
            } catch (IOException error) {
                lerr = error;
            }

            Thread.sleep(500);
        }
        throw new IOException("Python server did not respond. Restart ai_server.py and run App.", lerr);
    }

    private static void runMemoryManager() throws IOException, InterruptedException {
        Process process = new ProcessBuilder("python3", "memory_manager.py")
                .directory(BACKEND_DIR.toFile())
                .inheritIO()
                .start();
        int exitCode = process.waitFor();
        if (exitCode != 0) {
            throw new IOException("memory_manager.py failed with exit code " + exitCode);
        }
    }
    private static boolean runAi_server() throws IOException, InterruptedException {
        HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
        if (isServerHealthy(client)) {
            return false;
        }

        Process process = new ProcessBuilder("python3", "ai_server.py")
                .directory(BACKEND_DIR.toFile())
                .inheritIO()
                .start();
        try {
            waitForServer(client, process);
            return true;
        } catch (IOException | InterruptedException error) {
            if (process.isAlive()) {
                process.destroy();
            }
            throw error;
        }
    }

    private static boolean isServerHealthy(HttpClient client) throws InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(HEALTH_URI)
                .timeout(Duration.ofSeconds(2))
                .GET()
                .build();
        try {
            HttpResponse<Void> response = client.send(request, HttpResponse.BodyHandlers.discarding());
            return response.statusCode() == 200;
        } catch (IOException error) {
            return false;
        }
    }
    private static String runSupportPrompts() throws IOException, InterruptedException {
        Process process = new ProcessBuilder("python3", "support_prompts.py")
                .directory(BACKEND_DIR.toFile())
                .redirectErrorStream(true)
                .start();
        String guidance;
        try (var reader = process.inputReader(StandardCharsets.UTF_8)) {
            guidance = reader.lines().collect(java.util.stream.Collectors.joining("\n"));
        }
        int exitCode = process.waitFor();
        if (exitCode != 0) {
            throw new IOException("support_prompts.py failed with exit code " + exitCode);
        }
        return guidance;
    }

    private static Path findBackendDirectory() {
        Path workingDirectory = Path.of("").toAbsolutePath().normalize();
        List<Path> candidates = List.of(
                workingDirectory,
                workingDirectory.resolve("backend"),
                workingDirectory.resolve("..").resolve("backend").normalize(),
                workingDirectory.getParent() == null ? workingDirectory : workingDirectory.getParent()
        );
        for (Path candidate : candidates) {
            if (Files.isRegularFile(candidate.resolve("ai_server.py"))) {
                return candidate;
            }
        }
        throw new IllegalStateException(
                "Could not locate backend/ai_server.py from " + workingDirectory
        );
    }

    private static void sendError(HttpExchange exchange, int status, String message)
            throws IOException {
        sendJson(exchange, status, "{\"error\":\"" + jsonEscape(message) + "\"}");
    }

    private static void sendJson(HttpExchange exchange, int status, String response)
            throws IOException {
        byte[] resBytes = response.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        setCorsHeaders(exchange);
        exchange.sendResponseHeaders(status, resBytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(resBytes);
        }
    }

    private static void setCorsHeaders(HttpExchange exchange) {
        exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        exchange.getResponseHeaders().set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        exchange.getResponseHeaders().set(
                "Access-Control-Allow-Headers",
                "Content-Type, X-User-ID, X-Time-Zone-Offset-Minutes"
        );
    }

    private static String jsonEscape(String value) {
        return value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
    private static void getProgressHistory(HttpExchange exchange) throws IOException {
        String userId = exchange.getRequestHeaders().getFirst("X-User-ID");
        if (userId == null || userId.isBlank()) {
            sendError(exchange, 400, "X-User-ID header is required.");
            return;
        }

        synchronized (PROCESS_LOCK) {
            try {
                runAi_server();

                String encodedUserId = URLEncoder.encode(userId, StandardCharsets.UTF_8);
                URI historyUri = URI.create(
                        "http://127.0.0.1:5000/progress/history?user_id=" + encodedUserId
                );

                HttpRequest request = HttpRequest.newBuilder(historyUri)
                        .timeout(Duration.ofSeconds(10))
                        .GET()
                        .build();

                HttpClient client = HttpClient.newBuilder()
                        .connectTimeout(Duration.ofSeconds(2))
                        .build();

                HttpResponse<String> response = client.send(
                        request,
                        HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
                );

                sendJson(exchange, response.statusCode(), response.body());
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                sendError(exchange, 502, "Reading check-in history was interrupted.");
            } catch (IOException error) {
                sendError(exchange, 502, "Could not read check-in history: " + error.getMessage());
            }
        }
    }
}
