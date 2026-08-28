-- 1. Create the four user roles required by the hackathon guidelines
CREATE TYPE user_role AS ENUM ('student', 'alumni', 'business', 'administrator');

-- 2. Create the profiles table linked to Supabase authentication
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role user_role NOT NULL DEFAULT 'student',
  first_name TEXT,
  last_name TEXT,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Turn on Row Level Security (RLS) so data is secure
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 4. Create basic security policies
CREATE POLICY "Users can view their own profile" 
ON profiles FOR SELECT 
USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON profiles FOR UPDATE 
USING (auth.uid() = id);