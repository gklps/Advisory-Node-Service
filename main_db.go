package main

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
	port       = flag.String("port", "8082", "Server port")
	mode       = flag.String("mode", "release", "Server mode (debug/release)")
	corsOrigin = flag.String("cors", "*", "CORS allowed origins")
	
	// Database flags
	dbType     = flag.String("db-type", "sqlite", "Database type (sqlite/postgres)")
	dbHost     = flag.String("db-host", "localhost", "Database host")
	dbPort     = flag.Int("db-port", 5432, "Database port")
	dbName     = flag.String("db-name", "advisory_node.db", "Database name")
	dbUser     = flag.String("db-user", "postgres", "Database username")
	dbPassword = flag.String("db-password", "", "Database password")
	dbSSLMode  = flag.String("db-ssl", "disable", "Database SSL mode")
)

func main() {
	flag.Parse()

	// Set Gin mode
	gin.SetMode(*mode)

	// Initialize database storage
	dbConfig := storage.DBConfig{
		Type:     *dbType,
		Host:     *dbHost,
		Port:     *dbPort,
		Database: *dbName,
		Username: *dbUser,
		Password: *dbPassword,
		SSLMode:  *dbSSLMode,
	}

	dbStore, err := storage.NewDBStore(dbConfig)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	fmt.Printf("Connected to %s database\n", *dbType)

	// Initialize router
	router := gin.Default()

	// Configure CORS
	config := cors.DefaultConfig()
	config.AllowOrigins = []string{*corsOrigin}
	config.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept"}
	router.Use(cors.New(config))

	// Add request logging middleware
	router.Use(gin.Logger())

	// Add recovery middleware
	router.Use(gin.Recovery())

	// Initialize handlers with database store
	quorumHandler := handlers.NewDBQuorumHandler(dbStore)

	// Setup routes
	setupRoutes(router, quorumHandler)

	// Start cleanup goroutine
	go startCleanupRoutine(dbStore)

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

	fmt.Printf("\n===========================================\n")
	fmt.Printf("Advisory Node Service (Database Version)\n")
	fmt.Printf("===========================================\n")
	fmt.Printf("Port: %s\n", *port)
	fmt.Printf("Mode: %s\n", *mode)
	fmt.Printf("Database: %s\n", *dbType)
	if *dbType == "sqlite" {
		fmt.Printf("DB File: %s\n", *dbName)
	} else {
		fmt.Printf("DB Host: %s:%d\n", *dbHost, *dbPort)
		fmt.Printf("DB Name: %s\n", *dbName)
	}
	fmt.Printf("\n===========================================\n")
	fmt.Println("API Endpoints:")
	fmt.Println("  POST   /api/quorum/register           - Register a quorum")
	fmt.Println("  POST   /api/quorum/confirm-availability - Confirm quorum availability")
	fmt.Println("  GET    /api/quorum/available          - Get available quorums (with balance check)")
	fmt.Println("  PUT    /api/quorum/balance            - Update quorum balance")
	fmt.Println("  DELETE /api/quorum/unregister/:did    - Unregister a quorum")
	fmt.Println("  POST   /api/quorum/heartbeat          - Update quorum heartbeat")
	fmt.Println("  GET    /api/quorum/info/:did          - Get quorum information")
	fmt.Println("  GET    /api/quorum/health             - Get service health status")
	fmt.Println("  GET    /api/quorum/transactions       - Get transaction history")
	fmt.Printf("===========================================\n\n")
	
	fmt.Println("Balance Validation:")
	fmt.Println("  - Each quorum must have at least: transaction_amount / quorum_count")
	fmt.Println("  - Example: 100 RBT transaction with 7 quorums requires 14.29 RBT per quorum")
	fmt.Println("  - Example: 100 RBT transaction with 5 quorums requires 20 RBT per quorum")
	fmt.Printf("\n===========================================\n")

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("\nShutting down server...")
}

func setupRoutes(router *gin.Engine, handler *handlers.DBQuorumHandler) {
	// API version 1
	v1 := router.Group("/api")
	{
		quorum := v1.Group("/quorum")
		{
			// Registration and availability
			quorum.POST("/register", handler.RegisterQuorum)
			quorum.POST("/confirm-availability", handler.ConfirmAvailability)
			
			// Query endpoints (GET /available now requires transaction_amount parameter)
			quorum.GET("/available", handler.GetAvailableQuorums)
			quorum.GET("/info/:did", handler.GetQuorumInfo)
			quorum.GET("/health", handler.GetHealth)
			quorum.GET("/transactions", handler.GetTransactionHistory)
			
			// Management endpoints
			quorum.PUT("/balance", handler.UpdateQuorumBalance)
			quorum.DELETE("/unregister/:did", handler.UnregisterQuorum)
			quorum.POST("/heartbeat", handler.Heartbeat)
		}
	}

	// Root health check
	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "Advisory Node (DB Version)",
			"version": "2.0.0",
			"status":  "running",
			"database": *dbType,
		})
	})
}

func startCleanupRoutine(store *storage.DBStore) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		<-ticker.C
		removed := store.CleanupStaleQuorums()
		if removed > 0 {
			log.Printf("Marked %d stale quorums as unavailable\n", removed)
		}
	}
}