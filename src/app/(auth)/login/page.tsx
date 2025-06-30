
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { Eye, EyeOff, ShieldCheck, Sun, Moon, LockKeyhole } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { InvoChatLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { useToast } from '@/hooks/use-toast';
import { motion, AnimatePresence } from 'framer-motion';
import { Checkbox } from '@/components/ui/checkbox';
import { useTheme } from 'next-themes';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';

function GoogleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48px" height="48px">
      <path fill="#FFC107" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12s5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24s8.955,20,20,20s20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z" />
      <path fill="#FF3D00" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z" />
      <path fill="#4CAF50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36c-5.223,0-9.657-3.356-11.303-8H2.39v8.04C5.932,41.4,14.28,44,24,44z" />
      <path fill="#1976D2" d="M43.611,20.083H42V20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.574l6.19,5.238C39.986,37.151,44,31.2,44,24C44,22.659,43.862,21.35,43.611,20.083z" />
    </svg>
  );
}

function MicrosoftIcon({ className }: { className?: string }) {
    return (
        <svg className={className} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48px" height="48px">
            <path fill="#ff5722" d="M6,6H22V22H6z" transform="rotate(-180 14 14)"/>
            <path fill="#4caf50" d="M26,6H42V22H26z" transform="rotate(-180 34 14)"/>
            <path fill="#2196f3" d="M6,26H22V42H6z" transform="rotate(-180 14 34)"/>
            <path fill="#ffc107" d="M26,26H42V42H26z" transform="rotate(-180 34 34)"/>
        </svg>
    )
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button
      type="submit"
      disabled={pending}
      className="w-full h-12 text-base font-bold text-white transition-all duration-300 transform-gpu
                 bg-gradient-to-r from-purple-600 to-pink-600
                 hover:from-purple-700 hover:to-pink-700
                 hover:-translate-y-0.5
                 active:translate-y-0 active:scale-95"
    >
      {pending ? <motion.div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" /> : 'Sign In'}
    </Button>
  );
}

const PasswordInput = ({ id, name, required }: { id: string, name: string, required?: boolean }) => {
  const [showPassword, setShowPassword] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  return (
    <Popover open={isFocused} onOpenChange={setIsFocused}>
        <PopoverTrigger asChild>
            <div className="relative">
                <Input
                    id={id}
                    name={name}
                    type={showPassword ? 'text' : 'password'}
                    placeholder=" "
                    required={required}
                    autoComplete="current-password"
                    className="peer h-12 bg-white/5 border-white/20 text-white placeholder-transparent focus:border-purple-500"
                    onFocus={() => setIsFocused(true)}
                    onBlur={() => setIsFocused(false)}
                />
                <Label htmlFor={id} className="absolute left-3 -top-2.5 text-gray-400 text-sm transition-all bg-black/20 px-1
                                                peer-placeholder-shown:text-base peer-placeholder-shown:text-gray-400 peer-placeholder-shown:top-3.5 peer-placeholder-shown:bg-transparent peer-placeholder-shown:px-0
                                                peer-focus:-top-2.5 peer-focus:text-purple-400 peer-focus:text-sm peer-focus:bg-black/20 peer-focus:px-1">
                    Password
                </Label>
                <button
                    type="button"
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-white"
                    onClick={() => setShowPassword(prev => !prev)}
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                    tabIndex={-1}
                >
                    <AnimatePresence mode="wait" initial={false}>
                    <motion.div
                        key={showPassword ? 'eye-off' : 'eye'}
                        initial={{ rotate: -45, opacity: 0 }}
                        animate={{ rotate: 0, opacity: 1 }}
                        exit={{ rotate: 45, opacity: 0 }}
                        transition={{ duration: 0.2 }}
                    >
                        {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
                    </motion.div>
                    </AnimatePresence>
                </button>
            </div>
        </PopoverTrigger>
        <PopoverContent className="w-80">
            <div className="space-y-2">
                <h4 className="font-medium leading-none">Password Requirements</h4>
                <p className="text-sm text-muted-foreground">
                    Your password must be at least 6 characters long.
                </p>
            </div>
        </PopoverContent>
    </Popover>
  );
};

const AnimatedGradientBackground = () => (
    <div className="absolute inset-0 -z-10 h-full w-full bg-gray-950">
        <div className="absolute inset-0 h-full w-full bg-[radial-gradient(#e5e7eb_1px,transparent_1px)] [background-size:16px_16px] [mask-image:radial-gradient(ellipse_50%_50%_at_50%_50%,#000_70%,transparent_100%)] opacity-5"></div>
        <div className="absolute inset-0 h-full w-full bg-gradient-to-r from-purple-900/80 via-pink-900/80 to-rose-900/80 opacity-40 animate-background-pan [background-size:200%_200%]" />
    </div>
);

const ThemeToggle = () => {
    const { theme, setTheme } = useTheme();
    return (
        <button onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')} className="absolute top-4 right-4 p-2 rounded-full bg-white/10 hover:bg-white/20 transition-colors">
            {theme === 'dark' ? <Sun className="h-5 w-5 text-yellow-300" /> : <Moon className="h-5 w-5" />}
        </button>
    )
}

export default function LoginPage({ searchParams }: { searchParams?: { error?: string, message?: string } }) {
    const { toast } = useToast();
    const [hasError, setHasError] = useState(false);

    useEffect(() => {
        const error = searchParams?.error;
        if (error) {
            toast({
                variant: 'destructive',
                title: 'Login Failed',
                description: error,
            });
            setHasError(true);
            const timer = setTimeout(() => setHasError(false), 500); // Match animation duration
            return () => clearTimeout(timer);
        }
         if (searchParams?.message) {
            toast({
                title: 'Success',
                description: searchParams.message,
            });
        }
    }, [searchParams, toast]);
    
    const containerVariants = {
        hidden: { opacity: 0 },
        visible: {
            opacity: 1,
            transition: {
                staggerChildren: 0.1
            }
        }
    };
    
    const itemVariants = {
        hidden: { y: 20, opacity: 0 },
        visible: { y: 0, opacity: 1 }
    };

  return (
    <main className="relative min-h-dvh w-full overflow-hidden bg-gray-950 text-white font-sans">
      <AnimatedGradientBackground />
      <ThemeToggle />

      <div className="relative z-10 flex min-h-dvh w-full items-center justify-center p-4 lg:grid lg:grid-cols-10">
        <div className="hidden lg:col-span-6 lg:flex flex-col items-center justify-center p-12">
           <motion.div variants={itemVariants} className="text-left max-w-lg">
                <h2 className="text-5xl font-bold tracking-tighter text-white">Unlock Your Inventory's Potential.</h2>
                <p className="mt-4 text-lg text-gray-300">InvoChat provides the clarity you need to make smarter, faster, data-driven decisions.</p>
           </motion.div>
        </div>
        <div className="w-full max-w-md lg:col-span-4">
          <motion.div
            variants={containerVariants}
            initial="hidden"
            animate="visible"
            className={`w-full rounded-2xl border border-white/10 bg-black/10 p-6 shadow-2xl backdrop-blur-lg md:p-8 ${hasError ? 'animate-shake' : ''}`}
          >
            <motion.div 
                variants={itemVariants} 
                className="flex flex-col items-center justify-center mb-6 text-center"
            >
                 <Link href="/" className="group mb-2 flex flex-col items-center justify-center gap-2 text-4xl font-bold">
                    <motion.div 
                        initial={{ scale: 0.9, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ delay: 0.1, type: "spring", stiffness: 260, damping: 20 }}
                    >
                         <InvoChatLogo className="h-14 w-14 transition-all duration-300 group-hover:[filter:drop-shadow(0_0_8px_hsl(var(--primary)))]"/>
                    </motion.div>
                    <h1 className="text-white">InvoChat</h1>
                </Link>
                <p className="text-balance text-gray-300">Intelligent Inventory Management</p>
            </motion.div>
            
            <form action={login} className="grid gap-6">
              <CSRFInput />
              
              <motion.div variants={itemVariants} className="relative">
                <Input
                  id="email"
                  name="email"
                  type="email"
                  placeholder=" " 
                  required
                  autoComplete="email"
                  className="peer h-12 bg-white/5 border-white/20 text-white placeholder-transparent focus:border-purple-500"
                />
                 <Label htmlFor="email" className="absolute left-3 -top-2.5 text-gray-400 text-sm transition-all bg-black/20 px-1
                                                 peer-placeholder-shown:text-base peer-placeholder-shown:text-gray-400 peer-placeholder-shown:top-3.5 peer-placeholder-shown:bg-transparent peer-placeholder-shown:px-0
                                                 peer-focus:-top-2.5 peer-focus:text-purple-400 peer-focus:text-sm peer-focus:bg-black/20 peer-focus:px-1">
                    Email
                </Label>
              </motion.div>

              <motion.div variants={itemVariants}>
                 <PasswordInput id="password" name="password" required />
              </motion.div>
              
              <motion.div variants={itemVariants} className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                    <Checkbox id="remember" className="border-gray-500 data-[state=checked]:bg-purple-600 data-[state=checked]:border-purple-500"/>
                    <Label htmlFor="remember" className="text-sm text-gray-300 cursor-pointer">Remember me</Label>
                </div>
                <Link href="/forgot-password" className="text-sm text-purple-400 hover:text-purple-300 hover:underline">
                    Forgot password?
                </Link>
              </motion.div>

              <motion.div variants={itemVariants}>
                <SubmitButton />
              </motion.div>
            </form>

            <motion.div variants={itemVariants} className="relative my-6">
                <div className="absolute inset-0 flex items-center">
                    <span className="w-full border-t border-white/20"></span>
                </div>
                <div className="relative flex justify-center text-xs uppercase">
                    <span className="bg-black/20 px-2 text-gray-400 backdrop-blur-sm">Or continue with</span>
                </div>
            </motion.div>

            <motion.div variants={itemVariants} className="grid grid-cols-2 gap-4">
                <Button variant="outline" className="h-11 bg-white/5 border-white/20 text-white hover:bg-white/10 transition-colors">
                    <GoogleIcon className="mr-2 h-5 w-5" /> Google
                </Button>
                <Button variant="outline" className="h-11 bg-white/5 border-white/20 text-white hover:bg-white/10 transition-colors">
                    <MicrosoftIcon className="mr-2 h-5 w-5" /> Microsoft
                </Button>
            </motion.div>
            
            <motion.p variants={itemVariants} className="mt-8 text-center text-sm text-gray-400">
              Don&apos;t have an account?{" "}
              <Link href="/signup" className="font-semibold text-purple-400 hover:text-purple-300 hover:underline">
                Sign up
              </Link>
            </motion.p>
             <motion.div variants={itemVariants} className="mt-8 flex justify-center items-center gap-4 text-xs text-gray-500">
                <span className="flex items-center gap-1"><ShieldCheck className="h-3 w-3"/> SOC2 Compliant</span>
                 <span className="flex items-center gap-1"><LockKeyhole className="h-3 w-3"/> 256-bit Encryption</span>
                <span className="flex items-center gap-1"><ShieldCheck className="h-3 w-3"/> GDPR Ready</span>
            </motion.div>
          </motion.div>
        </div>
      </div>
    </main>
  );
}
