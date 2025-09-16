package memory

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/gklps/advisory-node/handlers"
	"github.com/gklps/advisory-node/storage"
)

var (
	port       = flag.String("port", "8080", "Server port")
	mode       = flag.String("mode", "release", "Server mode (debug/release)")
	corsOrigin = flag.String("cors", "*", "CORS allowed origins")
)

func main() {
	flag.Parse()

	// Set Gin mode
	gin.SetMode(*mode)

	// Initialize storage
	store := storage.NewMemoryStore()

	// Initialize router
	router := gin.Default()

	// Configure CORS
	config := cors.DefaultConfig()
	config.AllowOrigins = []string{*corsOrigin}
	config.AllowMethods = []string{"GET", "POST", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept"}
	router.Use(cors.New(config))

	// Add request logging middleware
	router.Use(gin.Logger())

	// Add recovery middleware
	router.Use(gin.Recovery())

	// Initialize handlers
	quorumHandler := handlers.NewQuorumHandler(store)

	// Setup routes
	setupRoutes(router, quorumHandler)

	// Start cleanup goroutine
	go startCleanupRoutine(store)

	// Start server
	srv := &http.Server{
		Addr:    ":" + *port,
		Handler: router,
	}

	// Handle graceful shutdown
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	fmt.Printf("Advisory Node Service started on port %s\n", *port)
	fmt.Printf("Mode: %s\n", *mode)
	fmt.Println("API Endpoints:")
	fmt.Println("  POST   /api/quorum/register           - Register a quorum")
	fmt.Println("  POST   /api/quorum/confirm-availability - Confirm quorum availability")
	fmt.Println("  GET    /api/quorum/available          - Get available quorums")
	fmt.Println("  DELETE /api/quorum/unregister/:did    - Unregister a quorum")
	fmt.Println("  POST   /api/quorum/heartbeat          - Update quorum heartbeat")
	fmt.Println("  GET    /api/quorum/info/:did          - Get quorum information")
	fmt.Println("  GET    /api/quorum/health             - Get service health status")

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("\nShutting down server...")
}

func setupRoutes(router *gin.Engine, handler *handlers.QuorumHandler) {
	// API version 1
	v1 := router.Group("/api")
	{
		quorum := v1.Group("/quorum")
		{
			// Registration and availability
			quorum.POST("/register", handler.RegisterQuorum)
			quorum.POST("/confirm-availability", handler.ConfirmAvailability)
			
			// Query endpoints
			quorum.GET("/available", handler.GetAvailableQuorums)
			quorum.GET("/info/:did", handler.GetQuorumInfo)
			quorum.GET("/health", handler.GetHealth)
			
			// Management endpoints
			quorum.DELETE("/unregister/:did", handler.UnregisterQuorum)
			quorum.POST("/heartbeat", handler.Heartbeat)
		}
	}

	// Root health check
	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "Advisory Node",
			"version": "1.0.0",
			"status":  "running",
		})
	})
}

func startCleanupRoutine(store *storage.MemoryStore) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		<-ticker.C
		removed := store.CleanupStaleQuorums()
		if removed > 0 {
			log.Printf("Cleaned up %d stale quorums\n", removed)
		}
	}
}