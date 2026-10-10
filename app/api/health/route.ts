import {NextResponse} from 'next/server';
export async function GET(){return NextResponse.json({status:'ok',service:'sesco-campaign-cloud',version:'0.12.0',release_stage:'acceptance_required'},{headers:{'Cache-Control':'no-store'}});}
