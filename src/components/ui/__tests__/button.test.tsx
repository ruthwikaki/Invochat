import React from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from '../button';
import { Plus } from 'lucide-react';

describe('Button', () => {
  it('renders a button element by default', () => {
    render(<Button>Test Button</Button>);
    const buttonElement = screen.getByRole('button', { name: /test button/i });
    expect(buttonElement).toBeInTheDocument();
  });

  it('applies default variants correctly', () => {
    render(<Button>Test Button</Button>);
    expect(screen.getByRole('button')).toHaveClass('bg-primary text-primary-foreground h-10 px-4 py-2');
  });

  it('applies specified variants correctly', () => {
    render(<Button variant="destructive" size="sm">Delete</Button>);
    const button = screen.getByRole('button');
    expect(button).toHaveClass('bg-destructive text-destructive-foreground');
    expect(button).toHaveClass('h-9 rounded-md px-3');
  });

  it('is disabled when the disabled prop is true', () => {
    const handleClick = jest.fn();
    render(<Button disabled onClick={handleClick}>Disabled Button</Button>);
    const button = screen.getByRole('button');
    expect(button).toBeDisabled();
    userEvent.click(button);
    expect(handleClick).not.toHaveBeenCalled();
  });

  it('renders as a different element when asChild is true', () => {
    render(
      <Button asChild>
        <a href="/">Link Button</a>
      </Button>
    );
    const linkElement = screen.getByRole('link', { name: /link button/i });
    expect(linkElement).toBeInTheDocument();
    expect(linkElement.tagName).toBe('A');
  });

  it('renders an icon when provided', () => {
    render(<Button size="icon"><Plus data-testid="icon" /></Button>);
    const icon = screen.getByTestId('icon');
    expect(icon).toBeInTheDocument();
  });
});
