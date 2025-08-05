package com.example.demo.exception;

import com.example.demo.dto.common.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingPathVariableException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;

import jakarta.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

/**
 * Global exception handler for Nebulax API responses.
 * Provides centralized error handling and consistent API response format.
 * Handles validation errors, business exceptions, and system errors with appropriate HTTP status codes.
 * 
 * @author Vikas Singh
 * @since August 4, 2025
 * @see com.example.demo.dto.common.ApiResponse
 * @see com.example.demo.exception.VideoNotFoundException
 * @see com.example.demo.exception.VideoProcessingException
 * @see com.example.demo.exception.S3OperationException
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(NoHandlerFoundException.class)
    public ResponseEntity<ApiResponse<Object>> handleNoHandlerFound(
            NoHandlerFoundException ex, HttpServletRequest request) {

        String message = String.format("Route not found: %s %s",
                ex.getHttpMethod(), ex.getRequestURL());

        log.warn("Route not found: {} {}", ex.getHttpMethod(), ex.getRequestURL());

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.NOT_FOUND.value());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(response);
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiResponse<Object>> handleMethodNotSupported(
            HttpRequestMethodNotSupportedException ex, HttpServletRequest request) {

        String message = String.format("Method %s not supported for route %s. Supported methods: %s",
                ex.getMethod(), request.getRequestURI(), String.join(", ", ex.getSupportedMethods()));

        log.warn("Method not supported: {}", message);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.METHOD_NOT_ALLOWED.value());
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).body(response);
    }

    @ExceptionHandler(MissingPathVariableException.class)
    public ResponseEntity<ApiResponse<Object>> handleMissingPathVariable(
            MissingPathVariableException ex, HttpServletRequest request) {

        String message = String.format("Missing required path variable '%s' for route %s %s",
                ex.getVariableName(), request.getMethod(), request.getRequestURI());

        log.warn("Missing path variable: {}", message);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value());
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ApiResponse<Object>> handleMissingRequestParameter(
            MissingServletRequestParameterException ex, HttpServletRequest request) {

        String message = String.format("Missing required request parameter '%s' of type %s for route %s %s",
                ex.getParameterName(), ex.getParameterType(), request.getMethod(), request.getRequestURI());

        log.warn("Missing request parameter: {}", message);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value());
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Object>> handleHttpMessageNotReadable(
            HttpMessageNotReadableException ex, HttpServletRequest request) {

        String message = String.format(
                "Invalid or missing request body for route %s %s. Please provide valid JSON data.",
                request.getMethod(), request.getRequestURI());

        log.warn("Invalid request body: {} - {}", request.getRequestURI(), ex.getMessage());

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value());
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Object>> handleTypeMismatch(
            MethodArgumentTypeMismatchException ex, HttpServletRequest request) {

        Class<?> requiredType = ex.getRequiredType();
        String typeName = requiredType != null ? requiredType.getSimpleName() : "unknown";

        String message = String.format("Invalid value '%s' for parameter '%s'. Expected type: %s",
                ex.getValue(), ex.getName(), typeName);

        log.warn("Type mismatch: {}", message);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value());
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Map<String, String>>> handleValidationExceptions(
            MethodArgumentNotValidException ex, HttpServletRequest request) {

        Map<String, String> errors = new HashMap<>();
        ex.getBindingResult().getAllErrors().forEach((error) -> {
            String fieldName = ((FieldError) error).getField();
            String errorMessage = error.getDefaultMessage();
            errors.put(fieldName, errorMessage);
        });

        String message = String.format("Validation failed for route %s %s",
                request.getMethod(), request.getRequestURI());

        log.warn("Validation failed: {}", errors);

        ApiResponse<Map<String, String>> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value(), errors);
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(VideoNotFoundException.class)
    public ResponseEntity<ApiResponse<Object>> handleVideoNotFound(
            VideoNotFoundException ex, HttpServletRequest request) {

        String message = String.format("Video not found: %s", ex.getMessage());
        log.error("Video not found for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage());

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.NOT_FOUND.value());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(response);
    }

    @ExceptionHandler(VideoProcessingException.class)
    public ResponseEntity<ApiResponse<Object>> handleVideoProcessing(
            VideoProcessingException ex, HttpServletRequest request) {

        String message = String.format("Video processing failed: %s", ex.getMessage());
        log.error("Video processing error for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage(), ex);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.INTERNAL_SERVER_ERROR.value());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }

    @ExceptionHandler(S3OperationException.class)
    public ResponseEntity<ApiResponse<Object>> handleS3Operation(
            S3OperationException ex, HttpServletRequest request) {

        String message = String.format("S3 operation failed: %s", ex.getMessage());
        log.error("S3 operation error for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage(), ex);

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.INTERNAL_SERVER_ERROR.value());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Object>> handleIllegalArgument(
            IllegalArgumentException ex, HttpServletRequest request) {

        String message = String.format("Invalid argument: %s", ex.getMessage());
        log.error("Illegal argument for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage());

        ApiResponse<Object> response = ApiResponse.error(message, HttpStatus.BAD_REQUEST.value());
        return ResponseEntity.badRequest().body(response);
    }

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<ApiResponse<Object>> handleRuntimeException(
            RuntimeException ex, HttpServletRequest request) {

        log.error("Runtime error for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage(), ex);

        ApiResponse<Object> response = ApiResponse.error(
                "An unexpected error occurred", HttpStatus.INTERNAL_SERVER_ERROR.value());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Object>> handleGenericException(
            Exception ex, HttpServletRequest request) {

        log.error("Unexpected error for route {} {}: {}",
                request.getMethod(), request.getRequestURI(), ex.getMessage(), ex);

        ApiResponse<Object> response = ApiResponse.error(
                "An internal server error occurred", HttpStatus.INTERNAL_SERVER_ERROR.value());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
    }
}