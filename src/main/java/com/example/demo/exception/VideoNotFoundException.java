package com.example.demo.exception;

/**
 * Exception thrown when a requested video cannot be found in the system.
 * This is typically thrown during video retrieval operations when the specified
 * video ID does not exist in the database or has been deleted.
 * 
 * @author Xander Billa
 * @since August 4, 2025
 * @see com.example.demo.service.VideoService#getVideoById(String)
 * @see com.example.demo.handler.GlobalExceptionHandler
 */
public class VideoNotFoundException extends RuntimeException {
    public VideoNotFoundException(String message) {
        super(message);
    }

    public VideoNotFoundException(String message, Throwable cause) {
        super(message, cause);
    }
}
