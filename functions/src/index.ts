// ===== THAY THẾ TOÀN BỘ TỆP CLOUD FUNCTION (v10.3 - Thêm totalBillDiscount) =====

import {
  onDocumentCreated,
  FirestoreEvent,
  QueryDocumentSnapshot,
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import moment from "moment-timezone";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "asia-southeast1" });

// ============================================================================
// HÀM TRỢ GIÚP: LẤY NGÀY BÁO CÁO (v7.1 - Giữ nguyên)
// ============================================================================
async function getReportDateInfoMoment(billData: {
  storeId: string,
  createdByUid: string,
  createdAt: admin.firestore.Timestamp,
}): Promise<{
  reportDateForTimestamp: Date; // 00:00 UTC
  reportDateString: string; // YYYY-MM-DD
  reportDayStartTimestamp: admin.firestore.Timestamp; // Giờ chốt sổ (Local)
}> {
  const storeId = billData.storeId as string;
  const createdByUid = billData.createdByUid as string;
  const paymentTimestamp = billData.createdAt as admin.firestore.Timestamp;
  const timeZone = "Asia/Ho_Chi_Minh";

  let cutoffHour = 0;
  let cutoffMinute = 0;
  let ownerUidToReadSettings = createdByUid;
  try {
    const creatorUserDoc = await db.collection("users").doc(createdByUid).get();
    if (creatorUserDoc.exists && creatorUserDoc.data()?.ownerUid) {
      ownerUidToReadSettings = creatorUserDoc.data()?.ownerUid;
    }
    const ownerSettingsDoc = await db.collection("users").doc(ownerUidToReadSettings).get();
    if (ownerSettingsDoc.exists) {
      cutoffHour = ownerSettingsDoc.data()?.reportCutoffHour ?? 0;
      cutoffMinute = ownerSettingsDoc.data()?.reportCutoffMinute ?? 0;
    }
  } catch (e) {
    console.warn(`[getReportDateInfoMoment v7.1] Lỗi tải cài đặt store: ${storeId}. Dùng 00:00.`, e);
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
// HÀM TRỢ GIÚP MỚI: Định nghĩa payload (v10.3)
// ============================================================================
type IncrementPayload = {
  billCount?: number;
  totalRevenue?: number;
  totalProfit?: number;
  totalDebt?: number;
  totalDiscount?: number; // Chiết khấu (món)
  totalBillDiscount?: number; // <-- THÊM MỚI: Chiết khấu (tổng đơn)
  totalVoucherDiscount?: number;
  totalPointsValue?: number;
  totalTax?: number;
  totalSurcharges?: number;
  totalCash?: number;
  totalOtherPayments?: number;
  totalOtherRevenue?: number;
  totalOtherExpense?: number;
};

// Định nghĩa dữ liệu sản phẩm
type ProductSaleData = {
  id: string;
  name: string;
  group: string;
  qty: number;
  revenue: number;
  discount: number;
};

// ============================================================================
// HÀM 1: TỔNG HỢP HÓA ĐƠN (v10.3)
// ============================================================================
export const aggregateDailyReportV10 = onDocumentCreated("bills/{billId}",
  async (event: FirestoreEvent<QueryDocumentSnapshot | undefined>) => {
    console.log("--- Bắt đầu aggregateDailyReport v10.3 ---");
    const snap = event.data;
    if (!snap) return;
    const billId = event.params.billId;
    const billData = snap.data();

    // 1. Kiểm tra
    if (billData.status !== "completed") return;
    if (!billData?.storeId || !billData.createdAt || !billData.createdByUid || !billData.createdByName) {
      console.error(`[DailyReport v10.3] Bill ${billId} thiếu trường.`);
      return;
    }

    const storeId = billData.storeId;
    const userId = billData.createdByUid;
    const userName = billData.createdByName;
    const eventTime = billData.createdAt;
    const items = (billData.items as any[]) || [];

    try {
      // 2. Lấy ngày báo cáo
      const { reportDateForTimestamp, reportDateString, reportDayStartTimestamp } = await getReportDateInfoMoment({
        storeId: storeId,
        createdByUid: userId,
        createdAt: eventTime,
      });

      // 3. Xử lý Items
      let totalLineItemDiscount = 0; // Chiết khấu (món)
      const productSalesMap = new Map<string, ProductSaleData>();

      for (const item of items) {
        if (!item || item.quantity <= 0) continue;

        const product = item.product as { [key: string]: any } | undefined;
        const isTimeBased = product?.serviceSetup?.isTimeBased === true;
        
        const itemPrice = (item.price as number) || 0; // Giá bán thực tế
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
      
      // --- SỬA LOGIC v10.3: Phân biệt 2 loại chiết khấu ---
      const totalBillDiscount = (billData.discount as number) || 0; // Chiết khấu (tổng đơn)
      // totalLineItemDiscount đã được tính ở trên // Chiết khấu (món)
      // ------------------------------------------------
      
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
      let cashAmount = 0;
      let otherPaymentsAmount = 0;
      const payments = billData.payments as Record<string, number> || {};
      for (const [method, amount] of Object.entries(payments)) {
        if (method.startsWith("Tiền mặt")) {
          cashAmount += amount;
        } else {
          otherPaymentsAmount += amount;
        }
      }
      
      const billPayload: IncrementPayload = {
        billCount: 1,
        totalRevenue: totalPayable,
        totalProfit: profit,
        totalDebt: debtAmount,
        totalDiscount: totalLineItemDiscount, // Chiết khấu (món)
        totalBillDiscount: totalBillDiscount, // <-- THÊM MỚI: Chiết khấu (tổng đơn)
        totalVoucherDiscount: voucherDiscount,
        totalPointsValue: pointsValue,
        totalTax: taxAmount,
        totalSurcharges: totalSurcharges,
        totalCash: cashAmount,
        totalOtherPayments: otherPaymentsAmount,
      };

      // 5. Chạy Transaction
      await db.runTransaction(async (transaction) => {
        // --- VÙNG ĐỌC (READS) ---
        const shiftsRef = db.collection("employee_shifts");
        const openShiftQuery = shiftsRef
          .where("storeId", "==", storeId)
          .where("userId", "==", userId)
          .where("reportDateKey", "==", reportDateString)
          .where("status", "==", "open")
          .orderBy("startTime", "desc")
          .limit(1);
        const shiftQuerySnapshot = await transaction.get(openShiftQuery);

        const reportId = `${storeId}_${reportDateString}`;
        const reportRef = db.collection("daily_reports").doc(reportId);
        const reportDoc = await transaction.get(reportRef);
        
        let closedShiftSnapshot: admin.firestore.QuerySnapshot | null = null;
        if (shiftQuerySnapshot.empty) {
          const closedShiftQuery = shiftsRef
            .where("storeId", "==", storeId)
            .where("userId", "==", userId)
            .where("reportDateKey", "==", reportDateString)
            .where("status", "==", "closed")
            .orderBy("endTime", "desc")
            .limit(1);
          closedShiftSnapshot = await transaction.get(closedShiftQuery);
        }

        // --- VÙNG GHI (WRITES) ---
        let shiftId: string;
        let startTime: admin.firestore.Timestamp;
        let isNewShift = false;

        if (!shiftQuerySnapshot.empty) {
          const shiftDoc = shiftQuerySnapshot.docs[0];
          shiftId = shiftDoc.id;
          startTime = shiftDoc.data().startTime as admin.firestore.Timestamp;
        } else {
          isNewShift = true;
          const newShiftRef = shiftsRef.doc();
          shiftId = newShiftRef.id;
          startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
            ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
            : reportDayStartTimestamp;
        }

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

          const shiftDataForSet = {
            ...billPayload,
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
            ...billPayload,
            products: shiftProductsPayload,
            shifts: {
              [shiftId]: shiftDataForSet,
            },
          });
        } else {
          // --- Cập nhật Báo Cáo Cũ ---
          const updatePayload: { [key: string]: any } = {};
          const shiftKeyPrefix = `shifts.${shiftId}`;
          
          // Cập nhật payload chính
          for (const [key, value] of Object.entries(billPayload)) {
            if (typeof value === "number" && value !== 0) {
              const increment = admin.firestore.FieldValue.increment(value);
              updatePayload[key] = increment;
              updatePayload[`${shiftKeyPrefix}.${key}`] = increment;
            }
          }

          // Cập nhật payload sản phẩm
          for (const [pId, pData] of productSalesMap.entries()) {
            const rootProductKey = `products.${pId}`;
            const shiftProductKey = `${shiftKeyPrefix}.products.${pId}`;
            const qtyInc = admin.firestore.FieldValue.increment(pData.qty);
            const revInc = admin.firestore.FieldValue.increment(pData.revenue);
            const discInc = admin.firestore.FieldValue.increment(pData.discount);

            // Cập nhật cấp độ TỔNG
            updatePayload[`${rootProductKey}.productId`] = pData.id;
            updatePayload[`${rootProductKey}.productName`] = pData.name;
            updatePayload[`${rootProductKey}.productGroup`] = pData.group;
            updatePayload[`${rootProductKey}.quantitySold`] = qtyInc;
            updatePayload[`${rootProductKey}.totalRevenue`] = revInc;
            updatePayload[`${rootProductKey}.totalDiscount`] = discInc;

            // Cập nhật cấp độ CA
            updatePayload[`${shiftProductKey}.productId`] = pData.id;
            updatePayload[`${shiftProductKey}.productName`] = pData.name;
            updatePayload[`${shiftProductKey}.productGroup`] = pData.group;
            updatePayload[`${shiftProductKey}.quantitySold`] = qtyInc;
            updatePayload[`${shiftProductKey}.totalRevenue`] = revInc;
            updatePayload[`${shiftProductKey}.totalDiscount`] = discInc;
          }

          // Kiểm tra nếu ca này mới
          const existingShiftData = reportDoc.data()?.shifts?.[shiftId];
          if (!existingShiftData) {
            updatePayload[`${shiftKeyPrefix}.shiftId`] = shiftId;
            updatePayload[`${shiftKeyPrefix}.userId`] = userId;
            updatePayload[`${shiftKeyPrefix}.userName`] = userName;
            updatePayload[`${shiftKeyPrefix}.startTime`] = startTime;
            updatePayload[`${shiftKeyPrefix}.status`] = "open";
            updatePayload[`${shiftKeyPrefix}.endTime`] = null;
            updatePayload[`${shiftKeyPrefix}.openingBalance`] = 0;
            // (Payload sản phẩm đã được thêm ở trên)
          }
          
          transaction.update(reportRef, updatePayload);
        }

        // GHI 3: Cập nhật lại bill
        transaction.update(snap.ref, {
          reportDateKey: reportDateString,
          shiftId: shiftId,
        });
      }); // --- KẾT THÚC TRANSACTION ---

      console.log(`[DailyReport v10.3] Ghi thành công bill ${billId} vào ca ${reportDateString}`);
    } catch (error) {
      console.error(`[DailyReport v10.3] LỖI ${billId}:`, error);
    }
  });

// ============================================================================
// HÀM 2: TỔNG HỢP PHIẾU THU/CHI (v2.4 - Sửa lỗi thiếu storeId - Giữ nguyên)
// ============================================================================
export const aggregateManualTransactionsV2 = onDocumentCreated("manual_cash_transactions/{txId}",
  async (event: FirestoreEvent<QueryDocumentSnapshot | undefined>) => {
    console.log("--- Bắt đầu aggregateManualTransactions v2.4 ---");
    const snap = event.data;
    if (!snap) return;
    const txId = event.params.txId;
    const txData = snap.data();

    // 1. Kiểm tra
    if (txData.status !== "completed") return;
    if (!txData?.storeId || !txData.date || !txData.userId || !txData.user || txData.amount == null) {
      console.error(`[ManualTx v2.4] Tx ${txId} thiếu trường.`);
      return;
    }

    const storeId = txData.storeId as string;
    const userId = txData.userId as string;
    const userName = txData.user as string;
    const eventTime = txData.date as admin.firestore.Timestamp;
    const amount = (txData.amount as number) || 0;
    if (amount === 0) return;

    try {
      // 2. Lấy ngày báo cáo
      const { reportDateForTimestamp, reportDateString, reportDayStartTimestamp } = await getReportDateInfoMoment({
        storeId: storeId,
        createdByUid: userId,
        createdAt: eventTime,
      });

      // 3. Chuẩn bị payload
      const txPayload: IncrementPayload = {
        totalOtherRevenue: (txData.type === "revenue") ? amount : 0,
        totalOtherExpense: (txData.type === "expense") ? amount : 0,
      };

      // 4. Chạy Transaction
      await db.runTransaction(async (transaction) => {
        // --- VÙNG ĐỌC (READS) ---
        const shiftsRef = db.collection("employee_shifts");
        const openShiftQuery = shiftsRef
          .where("storeId", "==", storeId)
          .where("userId", "==", userId)
          .where("reportDateKey", "==", reportDateString)
          .where("status", "==", "open")
          .orderBy("startTime", "desc")
          .limit(1);
        const shiftQuerySnapshot = await transaction.get(openShiftQuery);

        const reportId = `${storeId}_${reportDateString}`;
        const reportRef = db.collection("daily_reports").doc(reportId);
        const reportDoc = await transaction.get(reportRef);
        
        let closedShiftSnapshot: admin.firestore.QuerySnapshot | null = null;
        if (shiftQuerySnapshot.empty) {
          const closedShiftQuery = shiftsRef
            .where("storeId", "==", storeId)
            .where("userId", "==", userId)
            .where("reportDateKey", "==", reportDateString)
            .where("status", "==", "closed")
            .orderBy("endTime", "desc")
            .limit(1);
          closedShiftSnapshot = await transaction.get(closedShiftQuery);
        }

        // --- VÙNG GHI (WRITES) ---
        let shiftId: string;
        let startTime: admin.firestore.Timestamp;
        let isNewShift = false;

        if (!shiftQuerySnapshot.empty) {
          const shiftDoc = shiftQuerySnapshot.docs[0];
          shiftId = shiftDoc.id;
          startTime = shiftDoc.data().startTime as admin.firestore.Timestamp;
        } else {
          isNewShift = true;
          const newShiftRef = shiftsRef.doc();
          shiftId = newShiftRef.id;
          startTime = (closedShiftSnapshot && !closedShiftSnapshot.empty)
            ? closedShiftSnapshot.docs[0].data().endTime as admin.firestore.Timestamp
            : reportDayStartTimestamp;
        }

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
          };
          transaction.set(reportRef, {
            storeId: storeId,
            date: admin.firestore.Timestamp.fromDate(reportDateForTimestamp),
            openingBalance: 0,
            ...txPayload,
            products: {},
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
            updatePayload[`${shiftKeyPrefix}.products`] = {};
          }
          transaction.update(reportRef, updatePayload);
        }

        // GHI 3: Cập nhật lại phiếu
        transaction.update(snap.ref, {
          reportDateKey: reportDateString,
          shiftId: shiftId,
        });
      }); // --- KẾT THÚC TRANSACTION ---

      console.log(`[ManualTx v2.4] Ghi thành công Tx ${txId} vào ca ${reportDateString}`);
    } catch (error) {
      console.error(`[ManualTx v2.4] LỖI ${txId}:`, error);
    }
  });
