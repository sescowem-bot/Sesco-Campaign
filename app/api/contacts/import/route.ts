import {sameOrigin,boundedText,bodyErrorResponse} from '@/lib/security/request';
import {NextResponse} from 'next/server';
import {z} from 'zod';
import {contactsAccess} from '@/lib/contacts/access';
const schema=z.object({
 organization_id:z.string().uuid(),
 batch_key:z.string().uuid(),
 rows:z.array(z.object({
  first_name:z.string().trim().max(100),last_name:z.string().trim().max(100),
  email:z.string().trim().max(254),phone:z.string().trim().max(20),
  attributes:z.record(z.string().regex(/^[a-z][a-z0-9_]{0,39}$/),z.string().max(500)).refine(value=>Object.keys(value).length<=12).optional()
 }).strict()).min(1).max(100)
}).strict();
export async function POST(request:Request){
 try{
  if(!sameOrigin(request))return NextResponse.json({error:'Cross-origin requests are not allowed'},{status:403});
  const contentType=request.headers.get('content-type')||'';
  if(!contentType.toLowerCase().startsWith('application/json'))return NextResponse.json({error:'JSON required'},{status:415});
  const text=await boundedText(request,95000);
  const parsed=schema.safeParse(JSON.parse(text));
  if(!parsed.success)return NextResponse.json({error:'Invalid contact data or batch identifier'},{status:400});
  const {db,user,authorized}=await contactsAccess(parsed.data.organization_id);
  if(!user)return NextResponse.json({error:'Sign in required'},{status:401});
  if(!authorized)return NextResponse.json({error:'Not authorized'},{status:403});
  const {data,error}=await db.rpc('import_contact_batch',{p_org:parsed.data.organization_id,p_batch_key:parsed.data.batch_key,p_rows:parsed.data.rows});
  if(error)return NextResponse.json({error:'Contact import rejected: '+error.message},{status:422});
  const summary=Array.isArray(data)?data[0]:data;
  return NextResponse.json({inserted:summary?.inserted??0,skipped:summary?.skipped??0,rejected:summary?.rejected??0});
 }catch(e){const rejected=bodyErrorResponse(e);if(rejected)return rejected;return NextResponse.json({error:'Import request could not be processed'},{status:400});}
}
