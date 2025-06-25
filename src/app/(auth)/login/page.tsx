'use client';

import { useFormState, useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArvoLogo } from '@/components/invochat-logo';
import Link from 'next/link';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <Button 
      type="submit" 
      disabled={pending} 
      className="w-full bg-gradient-to-r from-[#8B5CF6] to-[#3B82F6] hover:from-[#7c4dff] hover:to-[#2575fc] text-white font-bold py-3 rounded-lg shadow-lg hover:scale-105 hover:shadow-xl transition-all duration-300"
    >
      {pending ? 'Signing in...' : 'Sign In'}
    </Button>
  );
}

const FloatingLabelInput = ({ id, name, type, label, required }: { id: string, name: string, type: string, label: string, required?: boolean }) => (
  <div className="relative">
    <Input
      id={id}
      name={name}
      type={type}
      placeholder=" " 
      required={required}
      className="block px-3.5 py-3 w-full text-sm text-white bg-white/10 rounded-lg border border-white/30 appearance-none focus:outline-none focus:ring-0 focus:border-[#8B5CF6] peer"
    />
    <Label
      htmlFor={id}
      className="absolute text-sm text-white/70 duration-300 transform -translate-y-4 scale-75 top-4 z-10 origin-[0] start-3 peer-focus:text-[#a78bfa] peer-placeholder-shown:scale-100 peer-placeholder-shown:translate-y-0 peer-focus:scale-75 peer-focus:-translate-y-4"
    >
      {label}
    </Label>
  </div>
);


export default function LoginPage() {
  const [state, formAction] = useFormState(login, undefined);

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-gradient-to-br from-[#667eea] to-[#764ba2] p-4 overflow-hidden relative font-body">
      <div className="absolute top-1/4 left-1/4 w-32 h-32 bg-white/5 rounded-full animate-float" style={{ animationDelay: '0s' }}></div>
      <div className="absolute top-1/2 right-1/4 w-48 h-48 bg-white/5 rounded-2xl animate-float" style={{ animationDelay: '2s' }}></div>
      <div className="absolute bottom-1/4 left-1/3 w-24 h-24 bg-white/5 rounded-full animate-float" style={{ animationDelay: '4s' }}></div>
      <div className="absolute bottom-1/2 right-1/3 w-16 h-16 bg-white/5 rounded-lg animate-float" style={{ animationDelay: '6s' }}></div>

      <div className="z-10 text-center mb-8">
        <div className="inline-block transition-transform hover:scale-110 animate-fade-in">
            <ArvoLogo className="h-16 w-16 text-3xl shadow-lg" />
        </div>
        <h1 className="text-4xl font-bold text-white mt-4 tracking-tight">ARVO</h1>
      </div>

      <div className="w-full max-w-sm z-10 bg-white/10 backdrop-blur-md rounded-2xl shadow-2xl border border-white/20 animate-fade-in" style={{ animationDelay: '200ms' }}>
        <div className="p-8 space-y-6">
          <div className="text-center">
            <h2 className="text-2xl font-semibold text-white">Welcome Back</h2>
            <p className="text-white/80 mt-1 text-sm">Sign in to access your inventory chat assistant.</p>
          </div>
          
          <form action={formAction} className="space-y-6">
            {state?.error && (
              <Alert variant="destructive" className="bg-red-500/80 border-0 text-white">
                <AlertDescription>{state.error}</AlertDescription>
              </Alert>
            )}
            
            <FloatingLabelInput id="email" name="email" type="email" label="Email" required />
            <FloatingLabelInput id="password" name="password" type="password" label="Password" required />

            <SubmitButton />
          </form>

          <div className="mt-6 text-center text-sm">
            <span className="text-white/70">Don&apos;t have an account?{' '}</span>
            <Link href="/signup" className="underline font-medium text-white hover:text-white/80 transition">
              Sign up
            </Link>
          </div>
        </div>
      </div>
       <p className="z-10 mt-8 text-sm text-white/60">
        Your intelligent inventory copilot
      </p>
    </div>
  );
}
