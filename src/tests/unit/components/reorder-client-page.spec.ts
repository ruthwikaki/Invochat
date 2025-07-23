import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ReorderClientPage } from '@/app/(app)/analytics/reordering/reorder-client-page';
import type { ReorderSuggestion } from '@/types';
import { useToast } from '@/hooks/use-toast';
import * as dataActions from '@/app/data-actions';

// Mock dependencies
vi.mock('@/hooks/use-toast', () => ({
  useToast: vi.fn(() => ({
    toast: vi.fn(),
  })),
}));

vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: vi.fn(),
    refresh: vi.fn(),
  }),
}));

vi.mock('@/app/data-actions', () => ({
    createPurchaseOrdersFromSuggestions: vi.fn(),
    exportReorderSuggestions: vi.fn(),
}));

vi.mock('@/lib/csrf-client', () => ({
    getCookie: vi.fn(),
    CSRF_FORM_NAME: 'csrf_token'
}));

const mockSuggestions: ReorderSuggestion[] = [
  {
    variant_id: 'v1',
    product_id: 'p1',
    sku: 'SKU001',
    product_name: 'Test Product 1',
    supplier_name: 'Test Supplier',
    supplier_id: 's1',
    current_quantity: 5,
    suggested_reorder_quantity: 50,
    unit_cost: 1000,
    base_quantity: 50,
    adjustment_reason: 'AI adjustment reason',
    seasonality_factor: 1.0,
    confidence: 0.8
  },
  {
    variant_id: 'v2',
    product_id: 'p2',
    sku: 'SKU002',
    product_name: 'Test Product 2',
    supplier_name: 'Test Supplier',
    supplier_id: 's1',
    current_quantity: 10,
    suggested_reorder_quantity: 25,
    unit_cost: 2000,
    base_quantity: 25,
    adjustment_reason: null,
    seasonality_factor: null,
    confidence: null
  },
];

describe('Component: ReorderClientPage', () => {

    beforeEach(() => {
        vi.clearAllMocks();
    });

    it('should render the table with initial suggestions', () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);

        expect(screen.getByText('AI-Enhanced Reorder Suggestions')).toBeInTheDocument();
        expect(screen.getByText('Test Product 1')).toBeInTheDocument();
        expect(screen.getByText('Test Product 2')).toBeInTheDocument();
        expect(screen.getAllByRole('checkbox')).toHaveLength(3); // 1 header + 2 rows
    });

    it('should render the empty state when no suggestions are provided', () => {
        render(<ReorderClientPage initialSuggestions={[]} />);

        expect(screen.getByText('No Reorder Suggestions')).toBeInTheDocument();
    });

    it('should show the action bar when an item is selected', async () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        
        // Action bar should not be visible initially
        expect(screen.queryByText(/item\(s\) selected/)).not.toBeInTheDocument();
        
        const checkboxes = screen.getAllByRole('checkbox');
        // Click the first row checkbox (index 1, as index 0 is the header)
        await fireEvent.click(checkboxes[1]);

        expect(screen.getByText('1 item(s) selected')).toBeInTheDocument();
        expect(screen.getByRole('button', { name: /Create PO\(s\)/ })).toBeInTheDocument();
    });

    it('should call createPurchaseOrdersFromSuggestions when the button is clicked', async () => {
        const mockToast = vi.fn();
        (useToast as vi.Mock).mockReturnValue({ toast: mockToast });
        vi.spyOn(dataActions, 'createPurchaseOrdersFromSuggestions').mockResolvedValue({ 
            success: true, 
            createdPoCount: 1 
        });
        
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);

        // Select an item first
        const checkboxes = screen.getAllByRole('checkbox');
        await fireEvent.click(checkboxes[1]);

        const createPoButton = screen.getByRole('button', { name: /Create PO\(s\)/ });
        await fireEvent.click(createPoButton);

        await waitFor(() => {
            expect(dataActions.createPurchaseOrdersFromSuggestions).toHaveBeenCalled();
        });
        
        await waitFor(() => {
            expect(mockToast).toHaveBeenCalledWith(expect.objectContaining({
                title: 'Purchase Orders Created!',
            }));
        });
    });
    
});
