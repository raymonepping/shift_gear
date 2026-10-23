export function capabilities(policies: string[]) {
  return {
    isAdmin: policies.includes('root'),
    isOperator: policies.includes('sg-operator'),
    isEngineer: policies.includes('sg-engineer'),
    isAuditor: policies.includes('sg-auditor'),
  }
}
