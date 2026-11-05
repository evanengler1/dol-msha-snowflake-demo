import { handle } from "@/lib/server/db"
import { getLists } from "@/lib/server/lists"

export const dynamic = "force-dynamic"

export async function GET() {
  return handle(() => getLists())
}
