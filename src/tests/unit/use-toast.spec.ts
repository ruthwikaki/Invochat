
import { renderHook, act } from '@testing-library/react';
import { useToast, reducer } from '../../hooks/use-toast';
import { describe, it, expect, vi } from 'vitest';

// Mock document for jsdom environment
const mockDocument = {
  getElementById: vi.fn(),
  createElement: vi.fn(() => ({
    focus: vi.fn(),
    setAttribute: vi.fn(),
    style: {}
  }))
}

vi.stubGlobal('document', mockDocument)

describe('useToast reducer', () => {
  it('should add a toast', () => {
    const initialState = { toasts: [] };
    const toast = { id: '1', title: 'Test', open: true, onOpenChange: () => {} };
    const action = { type: 'ADD_TOAST' as const, toast };
    const state = reducer(initialState, action);
    expect(state.toasts).toEqual([toast]);
  });

  it('should dismiss a toast', () => {
    const toast = { id: '1', title: 'Test', open: true, onOpenChange: () => {} };
    const initialState = { toasts: [toast] };
    const action = { type: 'DISMISS_TOAST' as const, toastId: '1' };
    const state = reducer(initialState, action);
    expect(state.toasts[0].open).toBe(false);
  });
});


describe('useToast hook', () => {
  it('should allow adding and dismissing toasts', () => {
    const { result } = renderHook(() => useToast());

    act(() => {
      result.current.toast({
        title: 'Test Toast',
        description: 'This is a test'
      });
    });

    expect(result.current.toasts).toHaveLength(1);

    act(() => {
      result.current.dismiss(result.current.toasts[0].id);
    });

    expect(result.current.toasts[0].open).toBe(false);
  });
});
