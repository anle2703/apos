// index.ts

import {
  onDocumentCreated,
  onDocumentWritten,
  FirestoreEvent,
  QueryDocumentSnapshot,
  DocumentSnapshot,
  Change,
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import moment from "moment-timezone";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as crypto from 'crypto';

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "asia-southeast1" });

// ============================================================================
// ĐỊNH NGHĨA TYPES
// ============================================================================

type IncrementPayload = {
  billCount?: number;
  totalRevenue?: number;
  totalProfit?: number;
  totalDebt?: number;
  totalDiscount?: number;
  totalBillDiscount?: number;
  totalVoucherDiscount?: number;
  totalPointsValue?: number;
  totalTax?: number;
  totalSurcharges?: number;
  totalCash?: number;
  totalOtherPayments?: number;
  totalOtherRevenue?: number;
  totalOtherExpense?: number;
  paymentMethods?: Record<string, number>; // <-- Map lưu chi tiết thanh toán
};

type ProductSaleData = {
  id: string;
  name: string;
  group: string;
  qty: number;
  revenue: number;
  discount: number;
};

// ============================================================================
// HÀM TRỢ GIÚP: LẤY NGÀY BÁO CÁO
// ============================================================================
// Tìm đến hàm getReportDateInfoMoment và thay thế toàn bộ nội dung hàm đó bằng đoạn này:

async function getReportDateInfoMoment(billData: {
  storeId: string,
  createdByUid: string,
  createdAt: admin.firestore.Timestamp,
}): Promise<{
  reportDateForTimestamp: Date;
  reportDateString: string;
  reportDayStartTimestamp: admin.firestore.Timestamp;
}> {
  const storeId = billData.storeId as string;
  const paymentTimestamp = billData.createdAt as admin.firestore.Timestamp;
  const timeZone = "Asia/Ho_Chi_Minh";

  let cutoffHour = 0;
  let cutoffMinute = 0;
  
  try {
    // Thay đổi: Đọc trực tiếp từ store_settings/{storeId}
    const settingsDoc = await db.collection("store_settings").doc(storeId).get();
    if (settingsDoc.exists) {
      const data = settingsDoc.data();
      cutoffHour = data?.reportCutoffHour ?? 0;
      cutoffMinute = data?.reportCutoffMinute ?? 0;
    }
  } catch (e) {
    console.warn(`[getReportDateInfoMoment] Lỗi tải cài đặt store: ${storeId}. Dùng 00:00.`, e);
  }

  const paymentTimeVN = moment(paymentTimestamp.toDate()).tz(timeZone);
  const cutoffTimeTodayVN = paymentTimeVN.clone().set({
    hour: cutoffHour, minute: cutoffMinute, second: 0, millisecond: 0,
  });

  let reportCalendarDateVN: moment.Moment;
  let reportDayStartMoment: moment.Moment;

  if (paymentTimeVN.isBefore(cutoffTimeTodayVN)) {
      reportCalendarDateVN = paymentTimeVN.clone().subtract(1, "day").set({ hour: 0, minute: 0, second: 0, millisecond: 0 });
      reportDayStartMoment = cutoffTimeTodayVN.clone().subtract(1, "day");
  } else {
      reportCalendarDateVN = paymentTimeVN.clone().set({ hour: 0, minute: 0, second: 0, millisecond: 0 });
      reportDayStartMoment = cutoffTimeTodayVN;
  }

  const reportDateString = reportCalendarDateVN.format("YYYY-MM-DD");
  
  const year = reportCalendarDateVN.year();
  const monthIndex = reportCalendarDateVN.month();
  const day = reportCalendarDateVN.date();
  const reportDateForTimestamp = new Date(Date.UTC(year, monthIndex, day, 0, 0, 0, 0));
  const reportDayStartTimestamp = admin.firestore.Timestamp.fromDate(reportDayStartMoment.toDate());

  return {
    reportDateForTimestamp: reportDateForTimestamp,
    reportDateString: reportDateString,
    reportDayStartTimestamp: reportDayStartTimestamp,
  };
}

// ============================================================================
// HÀM 1: TỔNG HỢP HÓA ĐƠN
// ============================================================================
export const aggregateDailyReportV10 = onDocumentCreated("bills/{billId}",
  async (event: FirestoreEvent<QueryDocumentSnapshot | undefined>) => {
    console.log("--- Bắt đầu aggregateDailyReport v10.6 (Fix Overlapping & Shift Logic) ---");
    const snap = event.data;
    if (!snap) return;
    const billId = event.params.billId;
    const billData = snap.data();

    // 1. Kiểm tra
    if (billData.status !== "completed") return;
    if (!billData?.storeId || !billData.createdAt || !billData.createdByUid || !billData.createdByName) {
      console.error(`[DailyReport] Bill ${billId} thiếu trường.`);
      return;
    }

    const storeId = billData.storeId;
    const userId = billData.createdByUid;
    const userName = billData.createdByName;
    const eventTime = billData.createdAt;
    const items = (billData.items as any[]) || [];
    
    // [FIX] Lấy shiftId từ App gửi lên
    const clientShiftId = billData.shiftId as string | undefined;

    try {
      // 2. Lấy ngày báo cáo
      const { reportDateForTimestamp, reportDateString, reportDayStartTimestamp } = await getReportDateInfoMoment({
        storeId: storeId,
        createdByUid: userId,
        createdAt: eventTime,
      });

      // 3. Xử lý Items & Discount
      let totalLineItemDiscount = 0; 
      const productSalesMap = new Map<string, ProductSaleData>();

      for (const item of items) {
        if (!item || item.quantity <= 0) continue;

        const product = item.product as { [key: string]: any } | undefined;
        const isTimeBased = product?.serviceSetup?.isTimeBased === true;
        
        const itemPrice = (item.price as number) || 0;
        const quantity = (item.quantity as number) || 0;
        const discVal = (item.discountValue as number) || 0;
        const discUnit = (item.discountUnit as string) || "%";
        
        let itemDiscountAmount = 0;
        let priceEditDiscount = 0;
        let manualDiscount = 0;
        const productListPrice = (product?.sellPrice as number) || itemPrice;

        if (isTimeBased) {
          if (discVal > 0) {
            if (discUnit === "%") manualDiscount = itemPrice * (discVal / 100);
            else manualDiscount = discVal;
          }
        } else {
          if (productListPrice > itemPrice) {
            priceEditDiscount = (productListPrice - itemPrice) * quantity;
          }
          if (discVal > 0) {
            if (discUnit === "%") manualDiscount = (productListPrice * (discVal / 100)) * quantity;
            else manualDiscount = discVal * quantity;
          }
        }
        
        itemDiscountAmount = priceEditDiscount + manualDiscount;
        totalLineItemDiscount += itemDiscountAmount;

        // Tổng hợp Sản phẩm
        if (product?.id && product.productName) {
          const productId = product.id as string;
          const totalRevenue = (item.subtotal as number) || 0;
          
          const existing = productSalesMap.get(productId);
          if (existing) {
            existing.qty += quantity;
            existing.revenue += totalRevenue;
            existing.discount += itemDiscountAmount;
          } else {
            productSalesMap.set(productId, {
              id: productId,
              name: product.productName as string,
              group: (product.productGroup as string) || "Khác",
              qty: quantity,
              revenue: totalRevenue,
              discount: itemDiscountAmount,
            });
          }
        }
      }

      // 4. Chuẩn bị payload chính
      const totalPayable = (billData.totalPayable as number) || 0;
      const debtAmount = (billData.debtAmount as number) || 0;
      const profit = (billData.totalProfit as number) || 0;
      const totalBillDiscount = (billData.discount as number) || 0;
      const voucherDiscount = (billData.voucherDiscount as number) || 0;
      const taxAmount = (billData.taxAmount as number) || 0;
      const pointsValue = (billData.customerPointsValue as number) || 0;
      
      const surchargesArray = (billData.surcharges as any[]) || [];
      const totalSurcharges = surchargesArray.reduce((sum, surcharge) => {
        if (surcharge.isPercent === true) {
          const subtotal = (billData.subtotal as number) || 0;
          return sum + (subtotal * (surcharge.amount || 0) / 100);
        }
        return sum + (surcharge.amount || 0);
      }, 0);

      // --- XỬ LÝ THANH TOÁN CHI TIẾT ---
      let cashAmount = 0;
      let otherPaymentsAmount = 0;
      const paymentMethodBreakdown: Record<string, number> = {}; 

      const payments = billData.payments as Record<string, number> || {};
      for (const [method, amount] of Object.entries(payments)) {
        if (method.startsWith("Tiền mặt")) {
          cashAmount += amount;
        } else {
          otherPaymentsAmount += amount;
        }
        // Lưu chi tiết cho map mới (Bao gồm cả tiền mặt và các loại khác)
        paymentMethodBreakdown[method] = (paymentMethodBreakdown[method] || 0) + amount;
      }
      
      const billPayload: IncrementPayload = {
        billCount: 1,
        totalRevenue: totalPayable,
        totalProfit: profit,
        totalDebt: debtAmount,
        totalDiscount: totalLineItemDiscount,
        totalBillDiscount: totalBillDiscount,
        totalVoucherDiscount: voucherDiscount,
        totalPointsValue: pointsValue,
        totalTax: taxAmount,
        totalSurcharges: totalSurcharges,
        totalCash: cashAmount,
        totalOtherPayments: otherPaymentsAmount,
        paymentMethods: paymentMethodBreakdown, // Lưu map chi tiết
      };

      // 5. Chạy Transaction
      await db.runTransaction(async (transaction) => {
        // --- VÙNG ĐỌC ---
        const shiftsRef = db.collection("employee_shifts");
        const reportId = `${storeId}_${reportDateString}`;
        const reportRef = db.collection("daily_reports").doc(reportId);
        const reportDoc = await transaction.get(reportRef);

        let shiftId: string;
        let startTime: admin.firestore.Timestamp;
        let isNewShift = false;

        // [LOGIC MỚI] Ưu tiên ID ca từ Client gửi lên
        if (clientShiftId) {
          shiftId = clientShiftId;
          const specificShiftDoc = await transaction.get(shiftsRef.doc(shiftId));
          
          if (specificShiftDoc.exists) {
            // Ca có tồn tại -> Lấy startTime thực tế của ca
            startTime = specificShiftDoc.data()?.startTime || reportDayStartTimestamp;
          } else {
            // Trường hợp hiếm: App gửi ID ca "ma" -> Coi như ca mới
            console.warn(`[DailyReport] Ca ${shiftId} không tồn tại trên Server. Tạo mới.`);
            isNewShift = true;
            
            const closedShiftQuery = shiftsRef
              .where("storeId", "==", storeId)
              .where("userId", "==", userId)
              .where("reportDateKey", "==", reportDateString)
              .where("status", "==", "closed")
              .orderBy("endTime", "desc")
              .limit(1);
            const closedShiftSnapshot = await transaction.get(closedShiftQuery);
            
            startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
              ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
              : reportDayStartTimestamp;
          }
        } 
        else {
          // [LOGIC CŨ] App không gửi shiftId -> Server tự tìm
          const openShiftQuery = shiftsRef
            .where("storeId", "==", storeId)
            .where("userId", "==", userId)
            .where("reportDateKey", "==", reportDateString)
            .where("status", "==", "open")
            .orderBy("startTime", "desc")
            .limit(1);
          const shiftQuerySnapshot = await transaction.get(openShiftQuery);
          
          if (!shiftQuerySnapshot.empty) {
            const shiftDoc = shiftQuerySnapshot.docs[0];
            shiftId = shiftDoc.id;
            startTime = shiftDoc.data().startTime as admin.firestore.Timestamp;
          } else {
            isNewShift = true;
            const newShiftRef = shiftsRef.doc();
            shiftId = newShiftRef.id;
            
            const closedShiftQuery = shiftsRef
              .where("storeId", "==", storeId)
              .where("userId", "==", userId)
              .where("reportDateKey", "==", reportDateString)
              .where("status", "==", "closed")
              .orderBy("endTime", "desc")
              .limit(1);
            const closedShiftSnapshot = await transaction.get(closedShiftQuery);

            startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
              ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
              : reportDayStartTimestamp;
          }
        }

        // --- VÙNG GHI ---

        // GHI 1: Tạo ca mới (nếu cần)
        if (isNewShift) {
          transaction.set(shiftsRef.doc(shiftId), {
            storeId: storeId,
            userId: userId,
            userName: userName,
            reportDateKey: reportDateString,
            startTime: startTime,
            endTime: null,
            status: "open",
            openingBalance: 0,
          });
        }

        // GHI 2: Cập nhật hoặc Tạo Báo Cáo Ngày
        if (!reportDoc.exists) {
          // --- Tạo Báo Cáo Mới ---
          const shiftProductsPayload: { [key: string]: any } = {};
          for (const [pId, pData] of productSalesMap.entries()) {
            shiftProductsPayload[pId] = {
              productId: pData.id,
              productName: pData.name,
              productGroup: pData.group,
              quantitySold: pData.qty,
              totalRevenue: pData.revenue,
              totalDiscount: pData.discount,
            };
          }

          // Tách paymentMethods ra để xử lý
          const { paymentMethods, ...restPayload } = billPayload;

          const shiftDataForSet = {
            ...restPayload,
            paymentMethods: paymentMethods, // Map chi tiết trong Ca
            shiftId: shiftId,
            userId: userId,
            userName: userName,
            startTime: startTime,
            status: "open",
            endTime: null,
            openingBalance: 0,
            products: shiftProductsPayload,
          };
          
          transaction.set(reportRef, {
            storeId: storeId,
            date: admin.firestore.Timestamp.fromDate(reportDateForTimestamp),
            openingBalance: 0,
            ...restPayload,
            paymentMethods: paymentMethods, // Map chi tiết trong Ngày
            products: shiftProductsPayload,
            shifts: {
              [shiftId]: shiftDataForSet,
            },
          });
        } else {
          // --- Cập nhật Báo Cáo Cũ ---
          const updatePayload: { [key: string]: any } = {};
          const shiftKeyPrefix = `shifts.${shiftId}`;
          
          // Cập nhật các trường số (billCount, revenue, etc)
          for (const [key, value] of Object.entries(billPayload)) {
            if (key !== 'paymentMethods' && typeof value === "number" && value !== 0) {
              const increment = admin.firestore.FieldValue.increment(value);
              updatePayload[key] = increment;
              updatePayload[`${shiftKeyPrefix}.${key}`] = increment;
            }
          }

          // Cập nhật chi tiết thanh toán (Từng key trong map)
          // LƯU Ý: Không được set paymentMethods = {} vì sẽ gây overlap field paths
          for (const [method, amount] of Object.entries(paymentMethodBreakdown)) {
            if (amount !== 0) {
              // Cấp Ngày
              updatePayload[`paymentMethods.${method}`] = admin.firestore.FieldValue.increment(amount);
              // Cấp Ca (tự động tạo map nếu chưa có)
              updatePayload[`${shiftKeyPrefix}.paymentMethods.${method}`] = admin.firestore.FieldValue.increment(amount);
            }
          }

          // Cập nhật sản phẩm
          for (const [pId, pData] of productSalesMap.entries()) {
            const rootProductKey = `products.${pId}`;
            const shiftProductKey = `${shiftKeyPrefix}.products.${pId}`;
            const qtyInc = admin.firestore.FieldValue.increment(pData.qty);
            const revInc = admin.firestore.FieldValue.increment(pData.revenue);
            const discInc = admin.firestore.FieldValue.increment(pData.discount);

            updatePayload[`${rootProductKey}.productId`] = pData.id;
            updatePayload[`${rootProductKey}.productName`] = pData.name;
            updatePayload[`${rootProductKey}.productGroup`] = pData.group;
            updatePayload[`${rootProductKey}.quantitySold`] = qtyInc;
            updatePayload[`${rootProductKey}.totalRevenue`] = revInc;
            updatePayload[`${rootProductKey}.totalDiscount`] = discInc;

            updatePayload[`${shiftProductKey}.productId`] = pData.id;
            updatePayload[`${shiftProductKey}.productName`] = pData.name;
            updatePayload[`${shiftProductKey}.productGroup`] = pData.group;
            updatePayload[`${shiftProductKey}.quantitySold`] = qtyInc;
            updatePayload[`${shiftProductKey}.totalRevenue`] = revInc;
            updatePayload[`${shiftProductKey}.totalDiscount`] = discInc;
          }

          // Khởi tạo ca mới nếu chưa có trong report (dù shiftId đã có)
          const existingShiftData = reportDoc.data()?.shifts?.[shiftId];
          if (!existingShiftData) {
            updatePayload[`${shiftKeyPrefix}.shiftId`] = shiftId;
            updatePayload[`${shiftKeyPrefix}.userId`] = userId;
            updatePayload[`${shiftKeyPrefix}.userName`] = userName;
            updatePayload[`${shiftKeyPrefix}.startTime`] = startTime;
            updatePayload[`${shiftKeyPrefix}.status`] = "open";
            updatePayload[`${shiftKeyPrefix}.endTime`] = null;
            updatePayload[`${shiftKeyPrefix}.openingBalance`] = 0;
            // [FIXED] KHÔNG set paymentMethods = {} hoặc products = {} ở đây
            // Firestore sẽ tự tạo khi update field con
          }
          
          transaction.update(reportRef, updatePayload);
        }

        // GHI 3: Cập nhật lại bill
        transaction.update(snap.ref, {
          reportDateKey: reportDateString,
          shiftId: shiftId,
        });
      });

      console.log(`[DailyReport] Ghi thành công bill ${billId}`);
    } catch (error) {
      console.error(`[DailyReport] LỖI ${billId}:`, error);
    }
  });

// ============================================================================
// HÀM 2: TỔNG HỢP PHIẾU THU/CHI
// ============================================================================
export const aggregateManualTransactionsV2 = onDocumentCreated("manual_cash_transactions/{txId}",
  async (event: FirestoreEvent<QueryDocumentSnapshot | undefined>) => {
    console.log("--- Bắt đầu aggregateManualTransactions v2.6 (Fix Overlapping & Shift Logic) ---");
    const snap = event.data;
    if (!snap) return;
    const txId = event.params.txId;
    const txData = snap.data();

    if (txData.status !== "completed") return;
    if (!txData?.storeId || !txData.date || !txData.userId || !txData.user || txData.amount == null) {
      console.error(`[ManualTx] Tx ${txId} thiếu trường.`);
      return;
    }

    const storeId = txData.storeId as string;
    const userId = txData.userId as string;
    const userName = txData.user as string;
    const eventTime = txData.date as admin.firestore.Timestamp;
    const amount = (txData.amount as number) || 0;
    if (amount === 0) return;

    // [FIX] Lấy shiftId từ App (nếu có)
    const clientShiftId = txData.shiftId as string | undefined;

    try {
      const { reportDateForTimestamp, reportDateString, reportDayStartTimestamp } = await getReportDateInfoMoment({
        storeId: storeId,
        createdByUid: userId,
        createdAt: eventTime,
      });

      const txPayload: IncrementPayload = {
        totalOtherRevenue: (txData.type === "revenue") ? amount : 0,
        totalOtherExpense: (txData.type === "expense") ? amount : 0,
      };

      await db.runTransaction(async (transaction) => {
        const shiftsRef = db.collection("employee_shifts");
        const reportId = `${storeId}_${reportDateString}`;
        const reportRef = db.collection("daily_reports").doc(reportId);
        const reportDoc = await transaction.get(reportRef);
        
        let shiftId: string;
        let startTime: admin.firestore.Timestamp;
        let isNewShift = false;

        // [LOGIC MỚI] Ưu tiên Client Shift ID
        if (clientShiftId) {
          shiftId = clientShiftId;
          const specificShiftDoc = await transaction.get(shiftsRef.doc(shiftId));
          if (specificShiftDoc.exists) {
            startTime = specificShiftDoc.data()?.startTime || reportDayStartTimestamp;
          } else {
            console.warn(`[ManualTx] Ca ${shiftId} không tồn tại. Tạo mới.`);
            isNewShift = true;
            // Logic tìm ca đóng gần nhất (fallback)
            const closedShiftQuery = shiftsRef
              .where("storeId", "==", storeId)
              .where("userId", "==", userId)
              .where("reportDateKey", "==", reportDateString)
              .where("status", "==", "closed")
              .orderBy("endTime", "desc")
              .limit(1);
            const closedShiftSnapshot = await transaction.get(closedShiftQuery);
            startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
              ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
              : reportDayStartTimestamp;
          }
        } 
        else {
          // [LOGIC CŨ] Server tự tìm
          const openShiftQuery = shiftsRef
            .where("storeId", "==", storeId)
            .where("userId", "==", userId)
            .where("reportDateKey", "==", reportDateString)
            .where("status", "==", "open")
            .orderBy("startTime", "desc")
            .limit(1);
          const shiftQuerySnapshot = await transaction.get(openShiftQuery);

          if (!shiftQuerySnapshot.empty) {
            const shiftDoc = shiftQuerySnapshot.docs[0];
            shiftId = shiftDoc.id;
            startTime = shiftDoc.data().startTime as admin.firestore.Timestamp;
          } else {
            isNewShift = true;
            const newShiftRef = shiftsRef.doc();
            shiftId = newShiftRef.id;
            const closedShiftQuery = shiftsRef
              .where("storeId", "==", storeId)
              .where("userId", "==", userId)
              .where("reportDateKey", "==", reportDateString)
              .where("status", "==", "closed")
              .orderBy("endTime", "desc")
              .limit(1);
            const closedShiftSnapshot = await transaction.get(closedShiftQuery);
            startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
              ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
              : reportDayStartTimestamp;
          }
        }

        // --- Vùng ghi ---
        if (isNewShift) {
          transaction.set(shiftsRef.doc(shiftId), {
            storeId: storeId,
            userId: userId,
            userName: userName,
            reportDateKey: reportDateString,
            startTime: startTime,
            endTime: null,
            status: "open",
            openingBalance: 0,
          });
        }

        if (!reportDoc.exists) {
          const shiftDataForSet = {
            ...txPayload,
            shiftId: shiftId,
            userId: userId,
            userName: userName,
            startTime: startTime,
            status: "open",
            endTime: null,
            openingBalance: 0,
            products: {},
            paymentMethods: {},
          };
          transaction.set(reportRef, {
            storeId: storeId,
            date: admin.firestore.Timestamp.fromDate(reportDateForTimestamp),
            openingBalance: 0,
            ...txPayload,
            products: {},
            paymentMethods: {},
            shifts: {
              [shiftId]: shiftDataForSet,
            },
          });
        } else {
          const updatePayload: { [key: string]: any } = {};
          const shiftKeyPrefix = `shifts.${shiftId}`;
          
          for (const [key, value] of Object.entries(txPayload)) {
            if (typeof value === "number" && value !== 0) {
              const increment = admin.firestore.FieldValue.increment(value);
              updatePayload[key] = increment;
              updatePayload[`${shiftKeyPrefix}.${key}`] = increment;
            }
          }

          const existingShiftData = reportDoc.data()?.shifts?.[shiftId];
          if (!existingShiftData) {
            updatePayload[`${shiftKeyPrefix}.shiftId`] = shiftId;
            updatePayload[`${shiftKeyPrefix}.userId`] = userId;
            updatePayload[`${shiftKeyPrefix}.userName`] = userName;
            updatePayload[`${shiftKeyPrefix}.startTime`] = startTime;
            updatePayload[`${shiftKeyPrefix}.status`] = "open";
            updatePayload[`${shiftKeyPrefix}.endTime`] = null;
            updatePayload[`${shiftKeyPrefix}.openingBalance`] = 0;
            // [FIXED] KHÔNG set paymentMethods = {} hoặc products = {}
          }
          transaction.update(reportRef, updatePayload);
        }

        transaction.update(snap.ref, {
          reportDateKey: reportDateString,
          shiftId: shiftId,
        });
      });

      console.log(`[ManualTx] Ghi thành công Tx ${txId}`);
    } catch (error) {
      console.error(`[ManualTx] LỖI ${txId}:`, error);
    }
  });

// ============================================================================
// HÀM 3: GỬI THÔNG BÁO KHI THANH TOÁN (MẶC ĐỊNH - KHÔNG CẦN FILE MP3)
// ============================================================================
export const sendPaymentNotification = onDocumentWritten("bills/{billId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined>) => {
    console.log(`--- [START] Trigger sendPaymentNotification cho bill: ${event.params.billId} ---`);
    
    if (!event.data) return;

    const billDoc = event.data.after;
    const billData = billDoc.data();

    // 1. Kiểm tra điều kiện
    if (!billData || billData.status !== "completed") return;

    // Tránh gửi lặp
    const billDocBefore = event.data.before;
    const billDataBefore = billDocBefore.data();
    if (billDataBefore && billDataBefore.status === "completed") {
      return;
    }

    // 2. Lấy thông tin
    const storeId = billData.storeId;
    const tableName = billData.tableName || "Mang đi";
    const totalPayable = billData.totalPayable || 0;
    
    // Lấy tên thu ngân và thời gian
    const cashierName = billData.paidByName || billData.createdByName || "Nhân viên";
    const paymentTimestamp = billData.paidAt || billData.createdAt;
    let timeString = "";
    
    try {
      if (paymentTimestamp && typeof paymentTimestamp.toDate === 'function') {
         timeString = moment(paymentTimestamp.toDate()).tz("Asia/Ho_Chi_Minh").format("HH:mm DD/MM");
      } else {
         timeString = moment().tz("Asia/Ho_Chi_Minh").format("HH:mm DD/MM");
      }
    } catch (e) {
      timeString = moment().tz("Asia/Ho_Chi_Minh").format("HH:mm");
    }

    const formattedMoney = new Intl.NumberFormat('vi-VN').format(totalPayable);

    try {
      // 3. Tìm User (Lấy Token từ Store Settings)
      const settingsDoc = await db.collection("store_settings").doc(storeId).get();
    
      if (!settingsDoc.exists) return;
      
      const settingsData = settingsDoc.data();
      const rawTokens = settingsData?.fcmTokens; // Mảng tokens nằm ở đây

      if (!rawTokens || !Array.isArray(rawTokens) || rawTokens.length === 0) return;

      // Lọc token hợp lệ và loại bỏ trùng lặp
      const uniqueTokens = [...new Set(rawTokens.filter(t => typeof t === 'string' && t.trim() !== ''))];
      
      if (uniqueTokens.length === 0) return;

      // 4. Gửi thông báo (Dùng âm thanh mặc định)
      const message = {
        notification: {
          title: `💰 + ${formattedMoney} đ`,
          body: `${tableName} - TN: ${cashierName} - Lúc: ${timeString}`,
        },
        android: {
          notification: {
            channelId: 'high_importance_channel_v4',
            sound: 'default',
            priority: 'high' as 'high', 
            visibility: 'public' as 'public',
          }
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              contentAvailable: true,
            }
          }
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          type: 'new_bill',
          billId: event.params.billId,
        },
        tokens: uniqueTokens,
      };

      await admin.messaging().sendEachForMulticast(message);
      console.log(`[Notification] Đã gửi cho ${cashierName} lúc ${timeString}`);

    } catch (error) {
      console.error("[Notification] Lỗi:", error);
    }
  }
);

// ============================================================================
// HÀM 4: CHECK TỒN KHO HÀNG NGÀY (CHẠY 08:00 SÁNG)
// ============================================================================
export const checkLowStockDaily = onSchedule(
  {
    schedule: "every day 08:00",
    timeZone: "Asia/Ho_Chi_Minh",
    region: "asia-southeast1",
    timeoutSeconds: 540,
  },
  async (event) => {
    console.log("--- BẮT ĐẦU CHECK TỒN KHO HÀNG NGÀY ---");

    try {
      // 1. Quét tất cả store_settings
      const settingsSnap = await db.collection("store_settings").get();

      if (settingsSnap.empty) {
        console.log("Không có store nào.");
        return;
      }

      // 2. Duyệt từng Store
      for (const doc of settingsSnap.docs) {
        const storeId = doc.id;
        const data = doc.data();
        
        // Lấy tokens từ store_settings
        const rawTokens = data.fcmTokens;

        // Nếu store không có token nào thì bỏ qua
        if (!rawTokens || !Array.isArray(rawTokens) || rawTokens.length === 0) {
            continue;
        }

        // Lọc token hợp lệ (Dùng uniqueTokens MỚI)
        const uniqueTokens = [...new Set(rawTokens.filter((t: any) => typeof t === 'string' && t.trim() !== ''))];
        
        if (uniqueTokens.length === 0) continue;

        // 3. Kiểm tra sản phẩm của store này
        const productsSnap = await db.collection("products")
            .where("storeId", "==", storeId)
            .get();

        let lowStockCount = 0;
        let exampleProductName = "";

        productsSnap.forEach((pDoc: QueryDocumentSnapshot) => {
            const p = pDoc.data();
            const stock = Number(p.stock || 0);
            const minStock = Number(p.minStock || 0);

            if (minStock > 0 && stock < minStock) {
                lowStockCount++;
                if (exampleProductName === "") exampleProductName = p.productName;
            }
        });

        // 4. Gửi thông báo
        if (lowStockCount > 0) {
            const title = "⚠️ Cảnh báo tồn kho";
            const body = lowStockCount === 1
                ? `"${exampleProductName}" sắp hết hàng.`
                : `Có ${lowStockCount} sản phẩm sắp hết hàng (${exampleProductName},...).`;

            const message = {
                notification: {
                    title: title,
                    body: body,
                },
                android: {
                    notification: {
                        channelId: 'high_importance_channel_v4',
                        priority: 'high' as 'high',
                        visibility: 'public' as 'public',
                    }
                },
                apns: {
                    payload: {
                        aps: {
                            sound: 'default',
                            contentAvailable: true,
                        }
                    }
                },
                data: {
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    type: 'low_stock',
                    storeId: storeId,
                },
                tokens: uniqueTokens,
            };

            await admin.messaging().sendEachForMulticast(message);
            console.log(`[LowStock] Đã gửi cho store ${storeId}: ${lowStockCount} sp.`);
        }
      }

    } catch (error) {
      console.error("[LowStock] Lỗi khi chạy job:", error);
    }
  }
);

// ============================================================================
// HÀM 5: QUÉT VÀ KHÓA TÀI KHOẢN HẾT HẠN (CHẠY 12:00 SÁNG HÀNG NGÀY)
// ============================================================================
export const checkExpiredSubscriptions = onSchedule(
  {
    schedule: "every day 12:00",
    timeZone: "Asia/Ho_Chi_Minh",
    region: "asia-southeast1",
    timeoutSeconds: 540,
  },
  async (event) => {
    console.log("--- BẮT ĐẦU QUÉT TÀI KHOẢN HẾT HẠN ---");
    const now = admin.firestore.Timestamp.now();
    const db = admin.firestore();
    const auth = admin.auth();

    try {
      // 1. Tìm các tài khoản CHỦ (owner) đã hết hạn
      const expiredOwnersQuery = db.collection("users")
        .where("role", "==", "owner") 
        .where("active", "==", true)
        .where("subscriptionExpiryDate", "<", now);

      const ownersSnapshot = await expiredOwnersQuery.get();

      if (ownersSnapshot.empty) {
        console.log("Không có tài khoản nào hết hạn hôm nay.");
        return;
      }

      console.log(`Tìm thấy ${ownersSnapshot.size} chủ cửa hàng hết hạn. Đang xử lý...`);

      const bulkWriter = db.bulkWriter();

      // 2. Duyệt từng ông chủ hết hạn
      for (const ownerDoc of ownersSnapshot.docs) {
        const ownerData = ownerDoc.data();
        const ownerUid = ownerDoc.id;
        const storeId = ownerData.storeId;

        console.log(`>> Xử lý Owner: ${ownerUid} (Store: ${storeId})`);

        // A. Khóa tài khoản CHỦ trong Firestore
        bulkWriter.update(ownerDoc.ref, { 
          active: false,
          inactiveReason: 'expired_subscription' 
        });

        // B. Thu hồi Token Auth của CHỦ (Chỉ Owner mới có Auth)
        try {
          await auth.revokeRefreshTokens(ownerUid);
          console.log(`   - Đã revoke token Auth của chủ.`);
        } catch (authError) {
          console.error(`   - Lỗi revoke token chủ ${ownerUid} (có thể user không tồn tại trên Auth):`, authError);
        }

        // C. Tìm và khóa tất cả NHÂN VIÊN của cửa hàng này
        if (storeId) {
          const employeesQuery = await db.collection("users")
            .where("storeId", "==", storeId)
            .where("role", "!=", "owner") // Tránh query lại ông chủ
            .where("active", "==", true)  // Chỉ khóa những đứa đang mở
            .get();

          if (!employeesQuery.empty) {
            console.log(`   - Tìm thấy ${employeesQuery.size} nhân viên cần khóa.`);
            employeesQuery.forEach((empDoc) => {
              // Khóa nhân viên trong Firestore
              // Lưu ý: Không gọi revokeRefreshTokens với nhân viên vì họ không có Auth
              bulkWriter.update(empDoc.ref, {
                active: false,
                inactiveReason: 'store_expired'
              });
            });
          }
        }
      }

      // 3. Thực thi tất cả lệnh ghi
      await bulkWriter.close();
      console.log("--- HOÀN TẤT QUÉT VÀ KHÓA TÀI KHOẢN ---");

    } catch (error) {
      console.error("Lỗi khi chạy job quét hết hạn:", error);
    }
  }
);

// HÀM LOGIN THÔNG MINH (CHỦ & NHÂN VIÊN)
export const loginEmployee = onCall(
  { region: "asia-southeast1" },
  async (request: CallableRequest) => {
    const { phoneNumber, password } = request.data;

    if (!phoneNumber || !password) {
      throw new HttpsError('invalid-argument', 'Thiếu thông tin đăng nhập');
    }

    // 1. Tìm user theo số điện thoại
    const userQuery = await db.collection('users')
      .where('phoneNumber', '==', phoneNumber)
      .limit(1)
      .get();

    if (userQuery.empty) {
      throw new HttpsError('not-found', 'Sai SĐT hoặc mật khẩu!');
    }

    const userDoc = userQuery.docs[0];
    const userData = userDoc.data();
    const uid = userDoc.id;

    // ============================================================
    // TRƯỜNG HỢP A: LÀ CHỦ CỬA HÀNG (OWNER)
    // ============================================================
    if (userData.role === 'owner') {
      // Chủ dùng Firebase Auth chuẩn, server không check password được.
      // Trả về Email để Client tự đăng nhập bằng SDK.
      return { 
        isOwner: true, 
        email: userData.email 
      };
    }

    // ============================================================
    // TRƯỜNG HỢP B: LÀ NHÂN VIÊN (EMPLOYEE)
    // ============================================================
    
    // 2. Check Active
    if (userData.active === false) {
      throw new HttpsError('permission-denied', 'Tài khoản nhân viên đã bị khóa.');
    }

    // 3. Mã hóa mật khẩu gửi lên để so sánh với DB
    const hashedPassword = crypto.createHash('sha256').update(password).digest('hex');

    if (userData.password !== hashedPassword) {
         throw new HttpsError('unauthenticated', 'Sai mật khẩu nhân viên.');
    }

    try {
      // 4. Tạo Custom Token cho nhân viên
      const customToken = await admin.auth().createCustomToken(uid, {
        role: userData.role || 'employee',
        storeId: userData.storeId
      });

      return { 
        isOwner: false,
        token: customToken 
      };
    } catch (error) {
      console.error("Lỗi tạo token:", error);
      throw new HttpsError('internal', 'Lỗi hệ thống khi tạo token (Kiểm tra IAM Role).');
    }
  }
);

// Hàm kiểm tra thông tin đăng ký (Public)
export const checkRegisterInfo = onCall(
  { region: "asia-southeast1" },
  async (request: CallableRequest) => {
    const { phoneNumber, storeId } = request.data;

    // 1. Kiểm tra SĐT
    if (phoneNumber) {
      const phoneQuery = await db.collection('users')
        .where('phoneNumber', '==', phoneNumber)
        .limit(1)
        .get();
      if (!phoneQuery.empty) {
        throw new HttpsError('already-exists', 'Số điện thoại này đã được sử dụng bởi cửa hàng khác.');
      }
    }

    // 2. Kiểm tra StoreId (Tên cửa hàng)
    if (storeId) {
      const storeQuery = await db.collection('users')
        .where('storeId', '==', storeId)
        .limit(1)
        .get();
      if (!storeQuery.empty) {
        throw new HttpsError('already-exists', 'Tên cửa hàng này đã tồn tại, vui lòng chọn tên khác.');
      }
    }

    return { valid: true };
  }
);
