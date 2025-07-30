-- This script seeds the database with test users and companies.
-- It is designed to be idempotent (safe to run multiple times).

DO $$
DECLARE
    -- Company 1: StyleHub
    stylehub_company_id UUID;
    stylehub_owner_id UUID;
    stylehub_admin_id UUID;
    stylehub_member_id UUID;

    -- Company 2: TechMart
    techmart_company_id UUID;
    techmart_owner_id UUID;
    techmart_admin_id UUID;
    techmart_member_id UUID;

    -- Company 3: HomeFinds
    homefinds_company_id UUID;
    homefinds_owner_id UUID;
    homefinds_admin_id UUID;
    homefinds_member_id UUID;

    -- Company 4: FitnessGear
    fitnessgear_company_id UUID;
    fitnessgear_owner_id UUID;
    fitnessgear_admin_id UUID;
    fitnessgear_member_id UUID;
    
    -- Company 5: BookNook
    booknook_company_id UUID;
    booknook_owner_id UUID;
    booknook_admin_id UUID;
    booknook_member_id UUID;

BEGIN
    -- Function to safely insert a user and return their ID
    CREATE OR REPLACE FUNCTION seed_test_user(
        p_email TEXT,
        p_password TEXT,
        p_company_name TEXT DEFAULT NULL
    ) RETURNS UUID AS
    $inner$
    DECLARE
        user_id UUID;
    BEGIN
        -- Check if user already exists
        SELECT id INTO user_id FROM auth.users WHERE email = p_email;

        -- If user does not exist, create them
        IF user_id IS NULL THEN
            user_id := gen_random_uuid();
            INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone, phone_confirmed_at, email_change, email_change_sent_at)
            VALUES ('00000000-0000-0000-0000-000000000000', user_id, 'authenticated', 'authenticated', p_email, crypt(p_password, gen_salt('bf')), now(), 'recov_token', now(), now(), json_build_object('provider', 'email', 'providers', ARRAY['email'], 'company_name', p_company_name), '{}', now(), now(), NULL, NULL, '', now());
        END IF;

        RETURN user_id;
    END;
    $inner$
    LANGUAGE plpgsql;

    -- ====================================================================
    -- ==                       CREATE USERS                           ==
    -- ====================================================================

    -- Company 1: StyleHub
    stylehub_owner_id := seed_test_user('owner_stylehub@test.com', 'StyleHub2024!', 'StyleHub');
    stylehub_admin_id := seed_test_user('admin_stylehub@test.com', 'StyleHub2024!');
    stylehub_member_id := seed_test_user('member_stylehub@test.com', 'StyleHub2024!');

    -- Company 2: TechMart
    techmart_owner_id := seed_test_user('owner_techmart@test.com', 'TechMart2024!', 'TechMart');
    techmart_admin_id := seed_test_user('admin_techmart@test.com', 'TechMart2024!');
    techmart_member_id := seed_test_user('member_techmart@test.com', 'TechMart2024!');

    -- Company 3: HomeFinds
    homefinds_owner_id := seed_test_user('owner_homefinds@test.com', 'HomeFinds2024!', 'HomeFinds');
    homefinds_admin_id := seed_test_user('admin_homefinds@test.com', 'HomeFinds2024!');
    homefinds_member_id := seed_test_user('member_homefinds@test.com', 'HomeFinds2024!');

    -- Company 4: FitnessGear
    fitnessgear_owner_id := seed_test_user('owner_fitnessgear@test.com', 'FitnessGear2024!', 'FitnessGear');
    fitnessgear_admin_id := seed_test_user('admin_fitnessgear@test.com', 'FitnessGear2024!');
    fitnessgear_member_id := seed_test_user('member_fitnessgear@test.com', 'FitnessGear2024!');

    -- Company 5: BookNook
    booknook_owner_id := seed_test_user('owner_booknook@test.com', 'BookNook2024!', 'BookNook');
    booknook_admin_id := seed_test_user('admin_booknook@test.com', 'BookNook2024!');
    booknook_member_id := seed_test_user('member_booknook@test.com', 'BookNook2024!');


    -- ====================================================================
    -- ==                   ASSIGN USERS TO COMPANIES                    ==
    -- ====================================================================

    -- The handle_new_user trigger automatically creates companies and assigns 'Owner' roles.
    -- We just need to fetch the company IDs and assign the other roles.

    -- Get Company IDs
    SELECT id INTO stylehub_company_id FROM public.companies WHERE owner_id = stylehub_owner_id;
    SELECT id INTO techmart_company_id FROM public.companies WHERE owner_id = techmart_owner_id;
    SELECT id INTO homefinds_company_id FROM public.companies WHERE owner_id = homefinds_owner_id;
    SELECT id INTO fitnessgear_company_id FROM public.companies WHERE owner_id = fitnessgear_owner_id;
    SELECT id INTO booknook_company_id FROM public.companies WHERE owner_id = booknook_owner_id;

    -- Assign Admins and Members
    -- StyleHub
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (stylehub_company_id, stylehub_admin_id, 'Admin') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (stylehub_company_id, stylehub_member_id, 'Member') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    -- TechMart
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (techmart_company_id, techmart_admin_id, 'Admin') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (techmart_company_id, techmart_member_id, 'Member') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    
    -- HomeFinds
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (homefinds_company_id, homefinds_admin_id, 'Admin') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (homefinds_company_id, homefinds_member_id, 'Member') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    -- FitnessGear
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (fitnessgear_company_id, fitnessgear_admin_id, 'Admin') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (fitnessgear_company_id, fitnessgear_member_id, 'Member') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    -- BookNook
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (booknook_company_id, booknook_admin_id, 'Admin') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;
    INSERT INTO public.company_users (company_id, user_id, role) VALUES (booknook_company_id, booknook_member_id, 'Member') ON CONFLICT (company_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    -- Clean up the temporary function
    DROP FUNCTION IF EXISTS seed_test_user(TEXT, TEXT, TEXT);
END $$;
