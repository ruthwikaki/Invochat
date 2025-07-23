

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ReorderClientPage } from '@/app/(app)/analytics/reordering/reorder-client-page';
import type { ReorderSuggestion } from '@/types';
import { useToast } from '@/hooks/use-toast';
import * as dataActions from '@/app/data-actions';
import * as csrf from '@/lib/csrf-client';

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

vi.mock('@/app/data-actions');
vi.mock('@/lib/csrf-client');


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
        (csrf.getCookie as vi.Mock).mockReturnValue('test-csrf-token');
    });

    it('should render the table with initial suggestions', () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        expect(screen.getByText('AI-Enhanced Reorder Suggestions')).toBeInTheDocument();
        expect(screen.getByText('Test Product 1')).toBeInTheDocument();
        expect(screen.getByText('Test Product 2')).toBeInTheDocument();
        expect(screen.getAllByRole('checkbox')).toHaveLength(3);
    });

    it('should show the action bar when items are selected, and hide it when all are deselected', async () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);

        // Action bar should not be visible initially because the default state is now empty
        expect(screen.queryByText(/item\(s\) selected/)).not.toBeInTheDocument();

        const checkboxes = screen.getAllByRole('checkbox');
        // Click the first row checkbox
        await fireEvent.click(checkboxes[1]);
        expect(screen.getByText('1 item(s) selected')).toBeInTheDocument();

        // Click the second row checkbox
        await fireEvent.click(checkboxes[2]);
        expect(screen.getByText('2 item(s) selected')).toBeInTheDocument();

        // Uncheck the first item
        await fireEvent.click(checkboxes[1]);
        expect(screen.getByText('1 item(s) selected')).toBeInTheDocument();
        
        // Uncheck the last item
        await fireEvent.click(checkboxes[2]);
        expect(screen.queryByText(/item\(s\) selected/)).not.toBeInTheDocument();
    });

    it('should call createPurchaseOrdersFromSuggestions when PO button is clicked', async () => {
        const mockToast = vi.fn();
        (useToast as vi.Mock).mockReturnValue({ toast: mockToast });
        vi.spyOn(dataActions, 'createPurchaseOrdersFromSuggestions').mockResolvedValue({ 
            success: true, 
            createdPoCount: 1 
        });
        
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        
        // Select an item to show the button
        const checkboxes = screen.getAllByRole('checkbox');
        await fireEvent.click(checkboxes[1]);

        const createPoButton = screen.getByRole('button', { name: /Create PO\(s\)/ });
        await fireEvent.click(createPoButton);

        await waitFor(() => {
            expect(dataActions.createPurchaseOrdersFromSuggestions).toHaveBeenCalled();
            expect(mockToast).toHaveBeenCalledWith(expect.objectContaining({
                title: 'Purchase Orders Created!',
            }));
        });
    });
});
