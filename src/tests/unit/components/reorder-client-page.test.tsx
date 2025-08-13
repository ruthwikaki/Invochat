

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ReorderClientPage } from '@/app/(app)/analytics/reordering/reorder-client-page';
import type { ReorderSuggestion } from '@/schemas/reorder';
import { useToast } from '@/hooks/use-toast';
import * as dataActions from '@/app/(app)/analytics/reordering/actions';
import * as csrf from '@/lib/csrf-client';
import React from 'react';

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

vi.mock('@/app/(app)/analytics/reordering/actions');
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
        (csrf.generateAndSetCsrfToken as any).mockImplementation((setter: (token: string) => void) => setter('test-csrf-token'));
    });

    it('should render the table with initial suggestions', () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        expect(screen.getByText('AI-Enhanced Reorder Suggestions')).toBeInTheDocument();
        expect(screen.getByText('Test Product 1')).toBeInTheDocument();
        expect(screen.getByText('Test Product 2')).toBeInTheDocument();
        expect(screen.getAllByRole('checkbox')).toHaveLength(3);
    });

    it('should show the empty state when no suggestions are provided', () => {
        render(<ReorderClientPage initialSuggestions={[]} />);

        expect(screen.getByText('All Good! No Reorders Needed')).toBeInTheDocument();
    });

    it('should show the action bar when an item is selected, and hide it when all are deselected', async () => {
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        const checkboxes = screen.getAllByRole('checkbox');
        const selectAllCheckbox = checkboxes[0];

        // Action bar should not be visible initially because selections start empty
        expect(screen.queryByText(/item\(s\) selected/)).not.toBeInTheDocument();

        // Select all items
        fireEvent.click(selectAllCheckbox);
        
        // Wait for state update and action bar to appear
        await waitFor(() => {
          expect(screen.getByText('2 item(s) selected')).toBeInTheDocument();
        });

        // Unselect all items
        fireEvent.click(selectAllCheckbox);
        
        // Wait for state update and action bar to disappear
        await waitFor(() => {
          expect(screen.queryByText(/item\(s\) selected/)).not.toBeInTheDocument();
        });

        // Check one item to ensure individual selection still works
        fireEvent.click(checkboxes[1]);
        await waitFor(() => {
          expect(screen.getByText('1 item(s) selected')).toBeInTheDocument();
        });
    });


    it('should call createPurchaseOrdersFromSuggestions when PO button is clicked', async () => {
        const mockToast = vi.fn();
        (useToast as any).mockReturnValue({ toast: mockToast });
        (dataActions.createPurchaseOrdersFromSuggestions as any).mockResolvedValue({ 
            success: true, 
            createdPoCount: 1 
        });
        
        render(<ReorderClientPage initialSuggestions={mockSuggestions} />);
        // Select an item to enable the button
        const firstCheckbox = screen.getAllByRole('checkbox')[1];
        fireEvent.click(firstCheckbox);

        await waitFor(() => {
            expect(screen.getByText('1 item(s) selected')).toBeInTheDocument();
        });

        const createPoButton = screen.getByRole('button', { name: /Create PO\(s\)/ });
        fireEvent.click(createPoButton);

        await waitFor(() => {
            expect(dataActions.createPurchaseOrdersFromSuggestions).toHaveBeenCalled();
            expect(mockToast).toHaveBeenCalledWith(expect.objectContaining({
                title: 'Purchase Orders Created!',
            }));
        });
    });
});

