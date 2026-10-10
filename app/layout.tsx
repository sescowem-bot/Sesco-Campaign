import type {Metadata} from 'next';
import type {CSSProperties} from 'react';
import {publishedSite} from '@/lib/cms/server';
import {contrastInk} from '@/lib/cms/content';
import './globals.css';
export const dynamic='force-dynamic';
export async function generateMetadata():Promise<Metadata>{const site=await publishedSite();return {title:{default:site.display_name,template:`%s | ${site.display_name}`},description:site.tagline};}
export default async function RootLayout({children}:{children:React.ReactNode}){const site=await publishedSite();const fonts={system:'system-ui, sans-serif',arial:'Arial, Helvetica, sans-serif',georgia:'Georgia, serif'};return <html lang="en"><body style={{'--brand':site.primary_color,'--brand-ink':contrastInk(site.primary_color),'--platform-font':fonts[site.font]} as CSSProperties}>{children}</body></html>;}
