export interface RealtimeAnalyticsData {
  totalRevenue: number;
  totalOrders: number;
  totalCustomers: number;
  recentOrders: any[];
  topProducts: any[];
  lowStockAlerts: any[];
  timestamp: string;
}

class RealtimeAnalyticsService {
  private subscribers: ((data: RealtimeAnalyticsData) => void)[] = [];
  private updateInterval: NodeJS.Timeout | null = null;
  private isActive = false;

  subscribe(callback: (data: RealtimeAnalyticsData) => void) {
    this.subscribers.push(callback);
    
    // Start polling if this is the first subscriber
    if (this.subscribers.length === 1 && !this.isActive) {
      this.startPolling();
    }
    
    // Return unsubscribe function
    return () => {
      this.subscribers = this.subscribers.filter(sub => sub !== callback);
      
      // Stop polling if no more subscribers
      if (this.subscribers.length === 0) {
        this.stopPolling();
      }
    };
  }

  private startPolling() {
    this.isActive = true;
    
    // Fetch initial data
    this.fetchAnalyticsData();
    
    // Set up polling every 30 seconds
    this.updateInterval = setInterval(() => {
      this.fetchAnalyticsData();
    }, 30000);
  }

  private stopPolling() {
    this.isActive = false;
    
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
      this.updateInterval = null;
    }
  }

  private async fetchAnalyticsData() {
    try {
      const response = await fetch('/api/analytics/realtime');
      if (response.ok) {
        const data: RealtimeAnalyticsData = await response.json();
        
        // Notify all subscribers
        this.subscribers.forEach(callback => callback(data));
      }
    } catch (error) {
      console.error('Failed to fetch realtime analytics:', error);
    }
  }

  // Method to manually trigger an update
  async refreshData() {
    if (this.isActive) {
      await this.fetchAnalyticsData();
    }
  }
}

// Export singleton instance
export const realtimeAnalytics = new RealtimeAnalyticsService();
