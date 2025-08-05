package com.example.demo.controller;

import com.example.demo.dto.common.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;

/**
 * Health check controller for monitoring application status.
 * Provides simple health check functionality without detailed metrics.
 * 
 * Features:
 * - Basic application health status monitoring
 * - Simple success/failure response
 * 
 * @author Vikas Singh
 * @since June 18, 2025
 * @see com.example.demo.dto.common.ApiResponse
 */
@RestController
@RequestMapping("${app.api.base-path}/health")
public class HealthController {

        /**
         * Performs application health check and returns simple health status.
         * 
         * This endpoint provides:
         * - Basic application health status
         * - Simple success/failure indication
         * 
         * @return ResponseEntity containing basic health check results
         */
        @GetMapping
        public ResponseEntity<ApiResponse<String>> getHealth() {
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
