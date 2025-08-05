package com.example.demo.controller;

import com.example.demo.dto.common.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;

/**
 * Health check controller for application monitoring.
 * 
 * @author Vikas Singh
 * @since August 5, 2025
 */
@RestController
@RequestMapping("${app.api.base-path}/health")
public class HealthController {

        /**
         * Health check endpoint to verify application status.
         * 
         * @return ResponseEntity with health status information
         */
        @GetMapping
        public ResponseEntity<ApiResponse<String>> health() {
                try {
                        ApiResponse<String> response = ApiResponse.<String>builder()
                                        .success(true)
                                        .message("Health check successful")
                                        .status(200)
                                        .timestamp(LocalDateTime.now())
                                        .build();

                        return ResponseEntity.ok(response);

                } catch (Exception e) {
                        ApiResponse<String> response = ApiResponse.<String>builder()
                                        .success(false)
                                        .message("Health check failed")
                                        .status(503)
                                        .timestamp(LocalDateTime.now())
                                        .build();

                        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(response);
                }
        }
}
