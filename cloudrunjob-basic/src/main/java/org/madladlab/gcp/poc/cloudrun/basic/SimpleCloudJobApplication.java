package org.madladlab.gcp.poc.cloudrun.basic;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

@SpringBootApplication
public class SimpleCloudJobApplication implements CommandLineRunner {

    private static final Logger LOG = LoggerFactory.getLogger(SimpleCloudJobApplication.class);
    private static final String VERSION = "1.1-gcp-batch";

    private final ObjectMapper json = new ObjectMapper();

    public static void main(String[] args) {
        LOG.info("Starting SimpleCloudJobApplication v{}", VERSION);
        System.exit(SpringApplication.exit(
                SpringApplication.run(SimpleCloudJobApplication.class, args)));
    }

    @Override
    public void run(String... args) throws Exception {
        final String opId = "batch-job-" + UUID.randomUUID();
        LOG.info("[{}] ==== Batch task started at {} ====", opId, Instant.now());

        if (args.length == 0) {
            LOG.warn("[{}] No command-line arguments supplied; nothing to process.", opId);
            return;
        }

        // ── 1. print raw arguments exactly once ────────────────────────────────
        LOG.info("[{}] Raw argument list ({} item{})", opId, args.length,
                 args.length == 1 ? "" : "s");
        for (int i = 0; i < args.length; i++) {
            LOG.info("[{}]   [{}] {}", opId, i, args[i]);
        }

        // ── 2. detect a single-argument JSON document -or- key=value pairs ────
        if (args.length == 1 && looksLikeJson(args[0])) {
            parseAndLogJson(opId, args[0]);
        } else {
            parseAndLogKeyValuePairs(opId, args);
        }

        LOG.info("[{}] ==== Batch task finished at {} ====", opId, Instant.now());
    }

    /* --------------------------------------------------------------------- */
    /* Helpers                                                               */
    /* --------------------------------------------------------------------- */

    private boolean looksLikeJson(String s) {
        s = s.trim();
        return (s.startsWith("{") && s.endsWith("}"))
            || (s.startsWith("[") && s.endsWith("]"));
    }

    private void parseAndLogJson(String opId, String jsonString) {
        try {
            Object tree = json.readTree(jsonString);
            String pretty = json.writerWithDefaultPrettyPrinter().writeValueAsString(tree);
            LOG.info("[{}] Detected JSON payload; parsed content:\n{}", opId, pretty);
        } catch (JsonProcessingException ex) {
            LOG.warn("[{}] Argument looked like JSON but could not be parsed: {}", opId, ex.getMessage());
        }
    }

    private void parseAndLogKeyValuePairs(String opId, String[] args) {
        Map<String, String> kv = new LinkedHashMap<>();
        for (String arg : args) {
            int eq = arg.indexOf('=');
            if (eq > 0 && eq < arg.length() - 1) {
                kv.put(arg.substring(0, eq), arg.substring(eq + 1));
            } else {
                kv.put("arg_" + kv.size(), arg);     // keep unmatched tokens
            }
        }
        if (kv.isEmpty()) {
            LOG.info("[{}] No key=value pairs detected; arguments logged above only.", opId);
            return;
        }
        LOG.info("[{}] Parsed key=value arguments:", opId);
        kv.forEach((k, v) -> LOG.info("[{}]   {} = {}", opId, k, v));
    }
}
