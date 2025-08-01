import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useToast, Toaster } from '@/hooks/use-toast';
import React from 'react';

// Wrapper component to provide the necessary context for the toast hook
const ToastWrapper = ({ children }: { children: React.ReactNode }) => (
  <>
    {children}
    <Toaster />
  </>
);


describe('useToast hook', () => {
  it('should allow adding and dismissing toasts', () => {
    const { result } = renderHook(() => useToast(), {
      wrapper: ({ children }) => <ToastWrapper>{children}</ToastWrapper>,
    });

    act(() => {
      result.current.toast({
        title: 'Test Toast',
        description: 'This is a test',
      });
    });

    expect(result.current.toasts).toHaveLength(1);
    expect(result.current.toasts[0].title).toBe('Test Toast');

    act(() => {
        if(result.current.toasts[0]?.id) {
            result.current.dismiss(result.current.toasts[0].id);
        }
    });
    
    expect(result.current.toasts[0].open).toBe(false);
  });
});
