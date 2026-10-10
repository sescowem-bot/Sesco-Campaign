'use client';
export default function ErrorPage({reset}:{reset:()=>void}){return <main className="shell section"><div className="panel"><h1>This page could not be loaded</h1><p>Please try again. If the problem continues, contact the platform operator.</p><button className="btn" onClick={reset}>Try again</button></div></main>;}
