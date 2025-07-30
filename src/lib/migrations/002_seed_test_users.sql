-- src/lib/migrations/002_seed_test_users.sql
-- This script seeds the database with test users and companies for development and testing.
-- It is designed to be idempotent, meaning it can be run multiple times safely.

DO $$
DECLARE
    -- Company 1: StyleHub
    stylehub_company_id uuid;
    stylehub_owner_id uuid;
    stylehub_admin_id uuid;
    stylehub_member_id uuid;

    -- Company 2: TechMart
    techmart_company_id uuid;
    techmart_owner_id uuid;
    techmart_admin_id uuid;
    techmart_member_id uuid;

    -- Company 3: HomeFinds
    homefinds_company_id uuid;
    homefinds_owner_id uuid;
    homefinds_admin_id uuid;
    homefinds_member_id uuid;

    -- Company 4: FitnessGear
    fitnessgear_company_id uuid;
    fitnessgear_owner_id uuid;
    fitnessgear_admin_id uuid;
    fitnessgear_member_id uuid;

    -- Company 5: BookNook
    booknook_company_id uuid;
    booknook_owner_id uuid;
    booknook_admin_id uuid;
    booknook_member_id uuid;

BEGIN
    -- === 1. Create StyleHub and its users ===

    -- Create Owner user. The handle_new_user() trigger will auto-create the company.
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone, phone_confirmed_at, email_change, email_change_sent_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'owner_stylehub@test.com', crypt('StyleHub2024!', gen_salt('bf')), now(), 'recov_token_1', now(), now(), '{"provider": "email", "providers": ["email"], "company_name": "StyleHub"}', '{}', now(), now(), NULL, NULL, '', now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO stylehub_owner_id;

    -- Retrieve the created company ID and owner ID
    SELECT id INTO stylehub_company_id FROM public.companies WHERE name = 'StyleHub';
    SELECT id INTO stylehub_owner_id FROM auth.users WHERE email = 'owner_stylehub@test.com';

    -- Create Admin user for StyleHub
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'admin_stylehub@test.com', crypt('StyleHub2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO stylehub_admin_id;
    SELECT id INTO stylehub_admin_id FROM auth.users WHERE email = 'admin_stylehub@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (stylehub_admin_id, stylehub_company_id, 'Admin') ON CONFLICT (user_id, company_id) DO NOTHING;

    -- Create Member user for StyleHub
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'member_stylehub@test.com', crypt('StyleHub2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO stylehub_member_id;
    SELECT id INTO stylehub_member_id FROM auth.users WHERE email = 'member_stylehub@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (stylehub_member_id, stylehub_company_id, 'Member') ON CONFLICT (user_id, company_id) DO NOTHING;


    -- === 2. Create TechMart and its users ===
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'owner_techmart@test.com', crypt('TechMart2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"], "company_name": "TechMart"}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO techmart_owner_id;
    SELECT id INTO techmart_company_id FROM public.companies WHERE name = 'TechMart';
    SELECT id INTO techmart_owner_id FROM auth.users WHERE email = 'owner_techmart@test.com';

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'admin_techmart@test.com', crypt('TechMart2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO techmart_admin_id;
    SELECT id INTO techmart_admin_id FROM auth.users WHERE email = 'admin_techmart@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (techmart_admin_id, techmart_company_id, 'Admin') ON CONFLICT (user_id, company_id) DO NOTHING;

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'member_techmart@test.com', crypt('TechMart2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO techmart_member_id;
    SELECT id INTO techmart_member_id FROM auth.users WHERE email = 'member_techmart@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (techmart_member_id, techmart_company_id, 'Member') ON CONFLICT (user_id, company_id) DO NOTHING;


    -- === 3. Create HomeFinds and its users ===
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'owner_homefinds@test.com', crypt('HomeFinds2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"], "company_name": "HomeFinds"}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO homefinds_owner_id;
    SELECT id INTO homefinds_company_id FROM public.companies WHERE name = 'HomeFinds';
    SELECT id INTO homefinds_owner_id FROM auth.users WHERE email = 'owner_homefinds@test.com';

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'admin_homefinds@test.com', crypt('HomeFinds2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO homefinds_admin_id;
    SELECT id INTO homefinds_admin_id FROM auth.users WHERE email = 'admin_homefinds@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (homefinds_admin_id, homefinds_company_id, 'Admin') ON CONFLICT (user_id, company_id) DO NOTHING;

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'member_homefinds@test.com', crypt('HomeFinds2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO homefinds_member_id;
    SELECT id INTO homefinds_member_id FROM auth.users WHERE email = 'member_homefinds@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (homefinds_member_id, homefinds_company_id, 'Member') ON CONFLICT (user_id, company_id) DO NOTHING;


    -- === 4. Create FitnessGear and its users ===
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'owner_fitnessgear@test.com', crypt('FitnessGear2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"], "company_name": "FitnessGear"}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO fitnessgear_owner_id;
    SELECT id INTO fitnessgear_company_id FROM public.companies WHERE name = 'FitnessGear';
    SELECT id INTO fitnessgear_owner_id FROM auth.users WHERE email = 'owner_fitnessgear@test.com';

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'admin_fitnessgear@test.com', crypt('FitnessGear2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO fitnessgear_admin_id;
    SELECT id INTO fitnessgear_admin_id FROM auth.users WHERE email = 'admin_fitnessgear@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (fitnessgear_admin_id, fitnessgear_company_id, 'Admin') ON CONFLICT (user_id, company_id) DO NOTHING;

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'member_fitnessgear@test.com', crypt('FitnessGear2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO fitnessgear_member_id;
    SELECT id INTO fitnessgear_member_id FROM auth.users WHERE email = 'member_fitnessgear@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (fitnessgear_member_id, fitnessgear_company_id, 'Member') ON CONFLICT (user_id, company_id) DO NOTHING;


    -- === 5. Create BookNook and its users ===
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'owner_booknook@test.com', crypt('BookNook2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"], "company_name": "BookNook"}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO booknook_owner_id;
    SELECT id INTO booknook_company_id FROM public.companies WHERE name = 'BookNook';
    SELECT id INTO booknook_owner_id FROM auth.users WHERE email = 'owner_booknook@test.com';

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'admin_booknook@test.com', crypt('BookNook2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO booknook_admin_id;
    SELECT id INTO booknook_admin_id FROM auth.users WHERE email = 'admin_booknook@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (booknook_admin_id, booknook_company_id, 'Admin') ON CONFLICT (user_id, company_id) DO NOTHING;

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', uuid_generate_v4(), 'authenticated', 'authenticated', 'member_booknook@test.com', crypt('BookNook2024!', gen_salt('bf')), now(), '{"provider": "email", "providers": ["email"]}', '{}', now(), now())
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO booknook_member_id;
    SELECT id INTO booknook_member_id FROM auth.users WHERE email = 'member_booknook@test.com';
    INSERT INTO public.company_users (user_id, company_id, role) VALUES (booknook_member_id, booknook_company_id, 'Member') ON CONFLICT (user_id, company_id) DO NOTHING;


    RAISE NOTICE 'Test user and company seeding complete.';
END $$;
