import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ShoppingCart, Package, Globe, Zap, CheckCircle, Clock, AlertCircle } from 'lucide-react';

const integrations = [
  {
    id: 'shopify',
    name: 'Shopify',
    description: 'Sync your Shopify store inventory and orders',
    icon: ShoppingCart,
    status: 'available',
    category: 'E-commerce',
    testId: 'shopify-integration'
  },
  {
    id: 'woocommerce',
    name: 'WooCommerce',
    description: 'Connect your WooCommerce store',
    icon: Package,
    status: 'available',
    category: 'E-commerce',
    testId: 'woocommerce-integration'
  },
  {
    id: 'amazon-fba',
    name: 'Amazon FBA',
    description: 'Manage your Amazon FBA inventory',
    icon: Globe,
    status: 'connected',
    category: 'Marketplace',
    testId: 'amazon-fba-integration'
  },
  {
    id: 'quickbooks',
    name: 'QuickBooks',
    description: 'Sync financial data with QuickBooks',
    icon: Zap,
    status: 'pending',
    category: 'Accounting',
    testId: 'quickbooks-integration'
  }
];

const getStatusBadge = (status: string) => {
  switch (status) {
    case 'connected':
      return <Badge variant="default" className="bg-green-100 text-green-800"><CheckCircle className="w-3 h-3 mr-1" />Connected</Badge>;
    case 'pending':
      return <Badge variant="secondary"><Clock className="w-3 h-3 mr-1" />Pending</Badge>;
    case 'available':
      return <Badge variant="outline"><AlertCircle className="w-3 h-3 mr-1" />Available</Badge>;
    default:
      return <Badge variant="outline">Unknown</Badge>;
  }
};

export default function IntegrationsPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Integrations"
        description="Connect your favorite platforms and tools to streamline your inventory management."
      />
      
      <div className="mt-6">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6" data-testid="integrations-grid">
          {integrations.map((integration) => {
            const Icon = integration.icon;
            return (
              <Card key={integration.id} className="hover:shadow-lg transition-shadow" data-testid={integration.testId}>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center space-x-3">
                      <div className="p-2 bg-blue-100 rounded-lg">
                        <Icon className="w-6 h-6 text-blue-600" />
                      </div>
                      <div>
                        <CardTitle className="text-lg">{integration.name}</CardTitle>
                        <CardDescription>{integration.category}</CardDescription>
                      </div>
                    </div>
                    {getStatusBadge(integration.status)}
                  </div>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground mb-4">
                    {integration.description}
                  </p>
                  <div className="flex justify-between items-center">
                    {integration.status === 'connected' ? (
                      <Button variant="outline" size="sm" data-testid={`${integration.id}-disconnect`}>
                        Disconnect
                      </Button>
                    ) : integration.status === 'pending' ? (
                      <Button variant="outline" size="sm" disabled data-testid={`${integration.id}-pending`}>
                        Connecting...
                      </Button>
                    ) : (
                      <Button size="sm" data-testid={`${integration.id}-connect`}>
                        Connect
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>

        <div className="mt-8">
          <Card data-testid="integration-stats">
            <CardHeader>
              <CardTitle>Integration Statistics</CardTitle>
              <CardDescription>Overview of your connected platforms</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-3 gap-4">
                <div className="text-center">
                  <div className="text-2xl font-bold text-green-600">1</div>
                  <div className="text-sm text-muted-foreground">Connected</div>
                </div>
                <div className="text-center">
                  <div className="text-2xl font-bold text-yellow-600">1</div>
                  <div className="text-sm text-muted-foreground">Pending</div>
                </div>
                <div className="text-center">
                  <div className="text-2xl font-bold text-blue-600">2</div>
                  <div className="text-sm text-muted-foreground">Available</div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </AppPage>
  );
}
